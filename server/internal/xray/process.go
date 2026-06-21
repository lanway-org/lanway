package xray

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/lanway-org/lanway/server/internal/config"
	"github.com/lanway-org/lanway/server/internal/store"
)

// Runner supervises the Xray core process and applies config changes by
// regenerating the config file and restarting the core. Restarts are cheap and
// only happen when the user set changes (create/delete/limit), which is rare.
type Runner struct {
	binary     string
	configPath string

	mu  sync.Mutex
	cmd *exec.Cmd
}

// NewRunner returns a Runner. binary is the path to the xray executable and
// configDir is where config.json is written.
func NewRunner(binary, configDir string) *Runner {
	return &Runner{
		binary:     binary,
		configPath: filepath.Join(configDir, "config.json"),
	}
}

// Apply writes a fresh config from cfg + users and (re)starts the core.
func (r *Runner) Apply(cfg *config.Config, users []*store.User) error {
	data, err := GenerateConfig(cfg, users)
	if err != nil {
		return fmt.Errorf("generate xray config: %w", err)
	}
	tmp := r.configPath + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return fmt.Errorf("write xray config: %w", err)
	}
	if err := os.Rename(tmp, r.configPath); err != nil {
		return fmt.Errorf("commit xray config: %w", err)
	}
	return r.restart()
}

func (r *Runner) restart() error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.cmd != nil && r.cmd.Process != nil {
		_ = r.cmd.Process.Kill()
		_, _ = r.cmd.Process.Wait()
		r.cmd = nil
	}

	cmd := exec.Command(r.binary, "run", "-config", r.configPath)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start xray: %w", err)
	}
	r.cmd = cmd

	// Reap the process in the background so a crash doesn't leave a zombie.
	go func() { _ = cmd.Wait() }()

	// Give the core a moment to bind its ports before returning.
	time.Sleep(300 * time.Millisecond)
	return nil
}

// Stop terminates the core if running.
func (r *Runner) Stop() {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.cmd != nil && r.cmd.Process != nil {
		_ = r.cmd.Process.Kill()
		_, _ = r.cmd.Process.Wait()
		r.cmd = nil
	}
}

// QueryUsage returns total (uplink+downlink) bytes per user id by querying the
// Xray stats API. Missing users simply have no entry.
func (r *Runner) QueryUsage(ctx context.Context) (map[string]int64, error) {
	out, err := r.api(ctx, "statsquery", "--server=127.0.0.1:"+strconv.Itoa(apiPort), "-pattern", "user>>>")
	if err != nil {
		return nil, err
	}
	var resp struct {
		Stat []struct {
			Name  string  `json:"name"`
			Value flexInt `json:"value"`
		} `json:"stat"`
	}
	if err := json.Unmarshal(out, &resp); err != nil {
		return nil, fmt.Errorf("parse stats: %w", err)
	}
	usage := make(map[string]int64)
	for _, s := range resp.Stat {
		// Names look like: user>>>UUID>>>traffic>>>uplink
		parts := strings.Split(s.Name, ">>>")
		if len(parts) < 4 {
			continue
		}
		usage[parts[1]] += int64(s.Value)
	}
	return usage, nil
}

// flexInt unmarshals a stat value whether Xray encodes it as a JSON number
// (1234) or, in some builds, a quoted string ("1234"). Either way it ends up an
// int64 — the mismatch here is what silently zeroed all traffic accounting.
type flexInt int64

func (f *flexInt) UnmarshalJSON(b []byte) error {
	s := strings.Trim(string(b), `"`)
	if s == "" || s == "null" {
		*f = 0
		return nil
	}
	v, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return err
	}
	*f = flexInt(v)
	return nil
}

func (r *Runner) api(ctx context.Context, args ...string) ([]byte, error) {
	full := append([]string{"api"}, args...)
	cmd := exec.CommandContext(ctx, r.binary, full...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("xray api %s: %w: %s", strings.Join(args, " "), err, stderr.String())
	}
	return stdout.Bytes(), nil
}

// GenerateRealityKeys runs `xray x25519` and returns the (private, public)
// base64 keypair used for REALITY.
func GenerateRealityKeys(binary string) (priv, pub string, err error) {
	cmd := exec.Command(binary, "x25519")
	var out bytes.Buffer
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		return "", "", fmt.Errorf("xray x25519: %w", err)
	}
	// Label formats differ by Xray version:
	//   old (≤1.8): "Private key: …"        / "Public key: …"
	//   new (v26):  "PrivateKey: …"          / "Password (PublicKey): …"  (+ "Hash32:")
	// Parse on the key/value colon and match by keyword so both work.
	sc := bufio.NewScanner(&out)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		idx := strings.Index(line, ":")
		if idx < 0 {
			continue
		}
		key := strings.ToLower(strings.TrimSpace(line[:idx]))
		val := strings.TrimSpace(line[idx+1:])
		if val == "" {
			continue
		}
		switch {
		case strings.Contains(key, "private"):
			priv = val
		case strings.Contains(key, "public") || strings.HasPrefix(key, "password"):
			pub = val
		}
	}
	if priv == "" || pub == "" {
		return "", "", fmt.Errorf("xray x25519: could not parse keypair from output")
	}
	return priv, pub, nil
}
