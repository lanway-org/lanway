package xray

import (
	"encoding/json"

	"github.com/lanway-org/lanway/server/internal/config"
	"github.com/lanway-org/lanway/server/internal/store"
)

// apiInboundTag and apiPort expose Xray's stats/handler gRPC API on localhost so
// the manager can poll per-user traffic without restarting the core.
const (
	apiInboundTag = "api"
	apiPort       = 10085
	vpnInboundTag = "vpn-in"
)

// GenerateConfig builds the full Xray configuration document for the given
// server config and the set of enabled users. The returned bytes can be written
// straight to Xray's config.json.
func GenerateConfig(cfg *config.Config, users []*store.User) ([]byte, error) {
	clients := make([]map[string]any, 0, len(users))
	for _, u := range users {
		if !u.Enabled {
			continue
		}
		client := map[string]any{
			"id":    u.ID,
			"email": u.ID, // email is Xray's stats key; we use the UUID
			"level": 0,
		}
		if cfg.Mode == config.ModeReality {
			client["flow"] = "xtls-rprx-vision"
		}
		clients = append(clients, client)
	}

	streamSettings := buildStreamSettings(cfg, users)
	// TCP keepalive on accepted connections: refreshes NAT/path state so idle
	// tunnels aren't silently dropped (the "internet goes dead until I
	// reconnect" symptom), and lets the server detect dead peers.
	streamSettings["sockopt"] = map[string]any{
		"tcpKeepAliveIdle":     30,
		"tcpKeepAliveInterval": 15,
		"tcpNoDelay":           true,
	}

	doc := map[string]any{
		"log": map[string]any{"loglevel": "warning"},
		"api": map[string]any{
			"tag":      apiInboundTag,
			"services": []string{"HandlerService", "StatsService"},
		},
		"stats": map[string]any{},
		"policy": map[string]any{
			"levels": map[string]any{
				// connIdle raises the idle cutoff, and uplinkOnly/downlinkOnly = 0
				// stops Xray from closing a connection shortly after one direction
				// goes quiet — both needed so long-lived WebSockets aren't culled.
				"0": map[string]any{
					"statsUserUplink":   true,
					"statsUserDownlink": true,
					"handshake":         8,
					"connIdle":          600,
					"uplinkOnly":        0,
					"downlinkOnly":      0,
				},
			},
			"system": map[string]any{
				"statsInboundUplink":   true,
				"statsInboundDownlink": true,
			},
		},
		"inbounds": []any{
			// Local API inbound (loopback only).
			map[string]any{
				"tag":      apiInboundTag,
				"listen":   "127.0.0.1",
				"port":     apiPort,
				"protocol": "dokodemo-door",
				"settings": map[string]any{"address": "127.0.0.1"},
			},
			// The public VPN inbound.
			map[string]any{
				"tag":      vpnInboundTag,
				"listen":   "0.0.0.0",
				"port":     cfg.VPNPort,
				"protocol": "vless",
				"settings": map[string]any{
					"clients":    clients,
					"decryption": "none",
				},
				"streamSettings": streamSettings,
				// routeOnly: sniff the destination domain for routing decisions
				// only, but still connect to the address the client gave us.
				// Without this, Xray re-resolves the domain itself, which breaks
				// endpoints like gateway.messenger.com (the Messenger WebSocket).
				"sniffing": map[string]any{
					"enabled":      true,
					"destOverride": []string{"http", "tls", "quic"},
					"routeOnly":    true,
				},
			},
		},
		"outbounds": []any{
			map[string]any{"protocol": "freedom", "tag": "direct"},
			map[string]any{"protocol": "blackhole", "tag": "blocked"},
		},
		"routing": map[string]any{
			"rules": []any{
				map[string]any{
					"type":        "field",
					"inboundTag":  []string{apiInboundTag},
					"outboundTag": "api",
				},
				// Drop traffic to private networks to avoid being an open relay
				// into the operator's own LAN.
				map[string]any{
					"type":        "field",
					"ip":          []string{"geoip:private"},
					"outboundTag": "blocked",
				},
			},
		},
	}

	return json.MarshalIndent(doc, "", "  ")
}

// buildStreamSettings returns the transport/security block for the VPN inbound,
// branching on the configured stealth mode.
func buildStreamSettings(cfg *config.Config, users []*store.User) map[string]any {
	if cfg.Mode == config.ModeProxy {
		// An existing reverse proxy (nginx) terminates TLS on 443 and forwards
		// the secret WebSocket path here as plaintext, so Xray runs WS only.
		return map[string]any{
			"network":  "ws",
			"security": "none",
			"wsSettings": map[string]any{"path": cfg.TLS.WSPath},
		}
	}

	if cfg.Mode == config.ModeTLS {
		return map[string]any{
			"network":  "ws",
			"security": "tls",
			"tlsSettings": map[string]any{
				"serverName": cfg.TLS.Domain,
				"certificates": []any{
					map[string]any{
						"certificateFile": cfg.TLS.CertPath,
						"keyFile":         cfg.TLS.KeyPath,
					},
				},
			},
			"wsSettings": map[string]any{"path": cfg.TLS.WSPath},
		}
	}

	// REALITY: collect every user's short id so each client validates.
	shortIDs := make([]string, 0, len(users)+1)
	shortIDs = append(shortIDs, "") // allow empty short id as a fallback
	for _, u := range users {
		if u.Enabled && u.ShortID != "" {
			shortIDs = append(shortIDs, u.ShortID)
		}
	}

	return map[string]any{
		"network":  "tcp",
		"security": "reality",
		"realitySettings": map[string]any{
			"show":        false,
			"dest":        cfg.Reality.Dest,
			"xver":        0,
			"serverNames": cfg.Reality.ServerNames,
			"privateKey":  cfg.Reality.PrivateKey,
			"shortIds":    shortIDs,
		},
	}
}
