// Command lanway runs the Lanway VPN management server: a small REST API that
// supervises an Xray core and exposes user management to the Manager app.
package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/lanway-org/lanway/server/internal/api"
	"github.com/lanway-org/lanway/server/internal/config"
	"github.com/lanway-org/lanway/server/internal/store"
	"github.com/lanway-org/lanway/server/internal/tlsutil"
	"github.com/lanway-org/lanway/server/internal/xray"
)

func main() {
	log.SetFlags(log.LstdFlags | log.LUTC)

	configDir := env("LANWAY_CONFIG_DIR", "/config")
	xrayBin := env("LANWAY_XRAY_BIN", "xray")

	cfg, err := config.Load(configDir)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	// Public host can be injected by the installer (it knows the droplet IP).
	if h := os.Getenv("LANWAY_PUBLIC_HOST"); h != "" && cfg.PublicHost != h {
		cfg.PublicHost = h
		if err := cfg.Save(configDir); err != nil {
			log.Fatalf("save config: %v", err)
		}
	}

	// For one-click provisioning the Manager pre-seeds the access key so it can
	// connect immediately without reading it back over SSH.
	if k := os.Getenv("LANWAY_API_KEY"); k != "" && cfg.APIKey != k {
		cfg.APIKey = k
		if err := cfg.Save(configDir); err != nil {
			log.Fatalf("save config: %v", err)
		}
	}

	// The installer can configure stealth mode and ports via environment. This
	// is how "behind an existing nginx" (proxy) deployments are set up.
	if applyEnvConfig(cfg) {
		if err := cfg.Save(configDir); err != nil {
			log.Fatalf("save config: %v", err)
		}
	}

	// Generate REALITY keys on first run.
	if cfg.Mode == config.ModeReality && cfg.Reality.PrivateKey == "" {
		priv, pub, err := xray.GenerateRealityKeys(xrayBin)
		if err != nil {
			log.Fatalf("generate reality keys: %v", err)
		}
		cfg.Reality.PrivateKey = priv
		cfg.Reality.PublicKey = pub
		if err := cfg.Save(configDir); err != nil {
			log.Fatalf("save config: %v", err)
		}
	}

	st, err := store.Open(configDir)
	if err != nil {
		log.Fatalf("open store: %v", err)
	}

	runner := xray.NewRunner(xrayBin, configDir)
	defer runner.Stop()

	svc, err := api.NewService(cfg, configDir, st, runner)
	if err != nil {
		log.Fatalf("init service: %v", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go svc.StartUsagePoller(ctx, 60*time.Second)

	// The management API is served over TLS (self-signed) so the access key is
	// never sent in cleartext. The Manager app trusts it via the bearer token.
	certPath, keyPath, err := tlsutil.EnsureCert(configDir)
	if err != nil {
		log.Fatalf("management cert: %v", err)
	}

	addr := net.JoinHostPort("0.0.0.0", strconv.Itoa(cfg.APIPort))
	srv := &http.Server{
		Addr:              addr,
		Handler:           svc.Router(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	printSummary(cfg)

	go func() {
		log.Printf("management API listening on https://%s", addr)
		if err := srv.ListenAndServeTLS(certPath, keyPath); err != nil && err != http.ErrServerClosed {
			log.Fatalf("http server: %v", err)
		}
	}()

	<-ctx.Done()
	log.Println("shutting down…")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdownCtx)
}

func printSummary(cfg *config.Config) {
	host := cfg.PublicHost
	if host == "" {
		host = "<your-server-ip>"
	}
	line := "════════════════════════════════════════════════════════════"
	fmt.Printf(`
%s
  Lanway server is ready.

  Stealth mode      : %s
  Manager API URL   : https://%s:%d
  Access key        : %s

  Open the Lanway Manager app and paste the API URL and access
  key above to start creating users.
%s
`, line, cfg.Mode, host, cfg.APIPort, cfg.APIKey, line)
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// applyEnvConfig overlays optional environment variables onto cfg, returning
// true if anything changed (so the caller persists it). Used by the installer
// to select a stealth mode without hand-editing lanway.json.
func applyEnvConfig(cfg *config.Config) bool {
	changed := false
	if m := os.Getenv("LANWAY_MODE"); m != "" && cfg.Mode != m {
		cfg.Mode = m
		changed = true
	}
	if d := os.Getenv("LANWAY_DOMAIN"); d != "" && cfg.TLS.Domain != d {
		cfg.TLS.Domain = d
		// In TLS/proxy modes the domain is also what clients connect to.
		if cfg.PublicHost == "" {
			cfg.PublicHost = d
		}
		changed = true
	}
	if p := os.Getenv("LANWAY_WS_PATH"); p != "" && cfg.TLS.WSPath != p {
		cfg.TLS.WSPath = p
		changed = true
	}
	if v := os.Getenv("LANWAY_VPN_PORT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && cfg.VPNPort != n {
			cfg.VPNPort = n
			changed = true
		}
	}
	if v := os.Getenv("LANWAY_PUBLIC_PORT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && cfg.PublicPort != n {
			cfg.PublicPort = n
			changed = true
		}
	}
	return changed
}
