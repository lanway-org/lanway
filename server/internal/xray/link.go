package xray

import (
	"fmt"
	"net"
	"net/url"
	"strconv"

	"github.com/lanway-org/lanway/server/internal/config"
	"github.com/lanway-org/lanway/server/internal/store"
)

// ShareLinks bundles the importable strings for a single user.
type ShareLinks struct {
	VLESS  string `json:"vless"`  // standard vless:// link (portable to any Xray client)
	Lanway string `json:"lanway"` // branded lanway:// deep link for one-tap import
	Label  string `json:"label"`  // display name shown in clients
}

// BuildLinks produces the vless:// and lanway:// share links for a user given
// the server configuration. The vless:// form is intentionally standards
// compliant so the same key also works in other Xray clients (v2rayNG, etc.).
func BuildLinks(cfg *config.Config, u *store.User) ShareLinks {
	host := cfg.PublicHost
	port := cfg.PublicPort

	q := url.Values{}
	q.Set("encryption", "none")
	q.Set("type", "tcp")

	switch cfg.Mode {
	case config.ModeTLS, config.ModeProxy:
		// VLESS + WebSocket + TLS over the operator's domain. In proxy mode an
		// existing nginx provides the TLS on 443; the client sees the same link.
		q.Set("type", "ws")
		q.Set("security", "tls")
		q.Set("sni", cfg.TLS.Domain)
		q.Set("host", cfg.TLS.Domain)
		q.Set("path", cfg.TLS.WSPath)
		q.Set("fp", "chrome")
		if host == "" {
			host = cfg.TLS.Domain
		}
	default:
		// REALITY (no domain): looks like a genuine TLS visit to Reality.Dest.
		q.Set("security", "reality")
		q.Set("flow", "xtls-rprx-vision")
		if len(cfg.Reality.ServerNames) > 0 {
			q.Set("sni", cfg.Reality.ServerNames[0])
		}
		q.Set("pbk", cfg.Reality.PublicKey)
		q.Set("sid", u.ShortID)
		q.Set("fp", "chrome")
	}

	// Label the key by the server address, never the user's name — the name is
	// only for the operator's own tracking and must not leak in a shared key.
	label := host
	if label == "" {
		label = "Lanway"
	}

	vlessURL := url.URL{
		Scheme:   "vless",
		User:     url.User(u.ID),
		Host:     net.JoinHostPort(host, strconv.Itoa(port)),
		RawQuery: q.Encode(),
		Fragment: label,
	}
	vless := vlessURL.String()

	// The branded deep link wraps the standard config so the Lanway app can
	// register a single URL scheme for one-tap import.
	lanway := "lanway://add?config=" + url.QueryEscape(vless) + "&name=" + url.QueryEscape(label)

	return ShareLinks{VLESS: vless, Lanway: lanway, Label: label}
}

// ValidateHost returns an error if the configured public host is empty.
func ValidateHost(cfg *config.Config) error {
	if cfg.PublicHost == "" && cfg.TLS.Domain == "" {
		return fmt.Errorf("server public host is not set; run the installer or set it via the API")
	}
	return nil
}
