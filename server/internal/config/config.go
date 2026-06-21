package config

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// Config holds the persistent server configuration. It lives in the config
// directory (default /config inside the container, /opt/lanway on the host)
// and is generated on first run.
type Config struct {
	// APIKey is the bearer token the Manager app must present. Generated once.
	APIKey string `json:"api_key"`

	// PublicHost is the address clients connect to (IP or domain).
	PublicHost string `json:"public_host"`

	// APIPort is the REST management port (default 8080).
	APIPort int `json:"api_port"`

	// VPNPort is the port Xray actually listens on (default 443). In "proxy"
	// mode this is a localhost-only port that an existing reverse proxy (nginx)
	// forwards to, while clients still connect on PublicPort.
	VPNPort int `json:"vpn_port"`

	// PublicPort is the port clients connect to. Defaults to VPNPort. It differs
	// only in "proxy" mode, where clients hit nginx on 443 but Xray listens on a
	// local port.
	PublicPort int `json:"public_port"`

	// Mode is one of:
	//   "reality" — no domain, REALITY camouflage (default)
	//   "tls"     — own domain, Xray terminates TLS + WebSocket
	//   "proxy"   — sit behind an existing nginx/site that already owns 443
	Mode string `json:"mode"`

	// Reality settings, used when Mode == "reality".
	Reality RealityConfig `json:"reality"`

	// TLS settings, used when Mode == "tls".
	TLS TLSConfig `json:"tls"`

	// CreatedAt is the first-run timestamp, used for uptime reporting.
	CreatedAt time.Time `json:"created_at"`
}

// RealityConfig describes the REALITY camouflage parameters. REALITY borrows
// the TLS handshake of a real, popular site (Dest/ServerName) so that, to a
// censor, the traffic is indistinguishable from a genuine visit to that site.
type RealityConfig struct {
	// Dest is the real site Xray forwards non-VPN handshakes to, e.g.
	// "www.microsoft.com:443".
	Dest string `json:"dest"`

	// ServerNames are the SNI values accepted (must match Dest's certificate).
	ServerNames []string `json:"server_names"`

	// PrivateKey / PublicKey are the x25519 keypair (base64, from `xray x25519`).
	PrivateKey string `json:"private_key"`
	PublicKey  string `json:"public_key"`

	// ShortIDs are accepted REALITY short IDs (hex). At least one, may be empty "".
	ShortIDs []string `json:"short_ids"`
}

// TLSConfig describes own-domain VLESS+WS+TLS mode (Let's Encrypt).
type TLSConfig struct {
	Domain   string `json:"domain"`
	CertPath string `json:"cert_path"`
	KeyPath  string `json:"key_path"`
	WSPath   string `json:"ws_path"` // e.g. /vpn
}

const (
	ModeReality = "reality"
	ModeTLS     = "tls"
	ModeProxy   = "proxy"

	defaultAPIPort = 8080
	defaultVPNPort = 443
	configFileName = "lanway.json"
)

// Load reads the config from dir, generating and persisting a fresh one on
// first run. Any zero-valued required fields are filled with defaults.
func Load(dir string) (*Config, error) {
	path := filepath.Join(dir, configFileName)

	data, err := os.ReadFile(path)
	if err == nil {
		var c Config
		if err := json.Unmarshal(data, &c); err != nil {
			return nil, fmt.Errorf("parse config %s: %w", path, err)
		}
		c.applyDefaults()
		return &c, nil
	}
	if !os.IsNotExist(err) {
		return nil, fmt.Errorf("read config %s: %w", path, err)
	}

	// First run: generate a new config.
	key, err := randomToken(32)
	if err != nil {
		return nil, fmt.Errorf("generate api key: %w", err)
	}
	c := &Config{
		APIKey:     key,
		APIPort:    defaultAPIPort,
		VPNPort:    defaultVPNPort,
		PublicPort: defaultVPNPort,
		Mode:       ModeReality,
		CreatedAt:  time.Now().UTC(),
		Reality: RealityConfig{
			Dest:        "www.microsoft.com:443",
			ServerNames: []string{"www.microsoft.com"},
		},
		TLS: TLSConfig{WSPath: "/vpn"},
	}
	if err := c.Save(dir); err != nil {
		return nil, err
	}
	return c, nil
}

// Save atomically writes the config to dir.
func (c *Config) Save(dir string) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("create config dir: %w", err)
	}
	path := filepath.Join(dir, configFileName)
	tmp := path + ".tmp"

	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal config: %w", err)
	}
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return fmt.Errorf("write config: %w", err)
	}
	if err := os.Rename(tmp, path); err != nil {
		return fmt.Errorf("commit config: %w", err)
	}
	return nil
}

func (c *Config) applyDefaults() {
	if c.APIPort == 0 {
		c.APIPort = defaultAPIPort
	}
	if c.VPNPort == 0 {
		c.VPNPort = defaultVPNPort
	}
	if c.PublicPort == 0 {
		c.PublicPort = c.VPNPort
	}
	if c.Mode == "" {
		c.Mode = ModeReality
	}
	if c.TLS.WSPath == "" {
		c.TLS.WSPath = "/vpn"
	}
}

// randomToken returns a URL-safe base64 token with n bytes of entropy.
func randomToken(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
