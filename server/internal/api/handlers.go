package api

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/lanway-org/lanway/server/internal/store"
	"github.com/lanway-org/lanway/server/internal/xray"
)

// Router builds the HTTP handler with auth applied to every route except health.
func (s *Service) Router() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /api/health", s.handleHealth)
	mux.HandleFunc("GET /api/stats", s.auth(s.handleStats))
	mux.HandleFunc("POST /api/usage/poll", s.auth(s.handlePollUsage))
	mux.HandleFunc("GET /api/users", s.auth(s.handleListUsers))
	mux.HandleFunc("POST /api/users", s.auth(s.handleCreateUser))
	mux.HandleFunc("DELETE /api/users/{id}", s.auth(s.handleDeleteUser))
	mux.HandleFunc("GET /api/users/{id}/key", s.auth(s.handleUserKey))

	return logRequests(mux)
}

// auth wraps a handler, requiring a matching "Authorization: Bearer <key>".
func (s *Service) auth(next http.HandlerFunc) http.HandlerFunc {
	want := []byte(s.cfg.APIKey)
	return func(w http.ResponseWriter, r *http.Request) {
		h := r.Header.Get("Authorization")
		got := []byte(strings.TrimPrefix(h, "Bearer "))
		if len(got) == 0 || subtle.ConstantTimeCompare(got, want) != 1 {
			writeError(w, http.StatusUnauthorized, "invalid or missing API key")
			return
		}
		next(w, r)
	}
}

func (s *Service) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "ok",
		"service": "lanway",
		"mode":    s.cfg.Mode,
		"version": Version,
	})
}

func (s *Service) handleStats(w http.ResponseWriter, r *http.Request) {
	users := s.store.List()
	var total int64
	for _, u := range users {
		total += u.UsedBytes
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"total_users":      len(users),
		"bandwidth_bytes":  total,
		"uptime_seconds":   int64(time.Since(s.cfg.CreatedAt).Seconds()),
		"public_host":      s.cfg.PublicHost,
		"mode":             s.cfg.Mode,
		"vpn_port":         s.cfg.VPNPort,
	})
}

// handlePollUsage forces an immediate traffic poll and reports the result, so
// the Manager's refresh shows usage without waiting for the 60s background tick.
func (s *Service) handlePollUsage(w http.ResponseWriter, r *http.Request) {
	res := s.PollNow(r.Context())
	writeJSON(w, http.StatusOK, map[string]any{
		"stat_entries": res.StatEntries,
		"total_bytes":  res.TotalBytes,
		"error":        res.Error,
	})
}

func (s *Service) handleListUsers(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"users": s.store.List()})
}

type createUserRequest struct {
	Name        string  `json:"name"`
	DataLimitGB float64 `json:"data_limit_gb"`
}

func (s *Service) handleCreateUser(w http.ResponseWriter, r *http.Request) {
	var req createUserRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<16)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	if req.DataLimitGB < 0 {
		writeError(w, http.StatusBadRequest, "data_limit_gb must be >= 0")
		return
	}

	u, err := s.store.Create(req.Name, req.DataLimitGB)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not create user")
		return
	}
	if err := s.rebuild(); err != nil {
		// Roll back so we don't advertise a user the core doesn't know.
		_ = s.store.Delete(u.ID)
		writeError(w, http.StatusInternalServerError, "could not apply server config")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"user":  u,
		"links": xray.BuildLinks(s.cfg, u),
	})
}

func (s *Service) handleDeleteUser(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := s.store.Delete(id); err != nil {
		if errors.Is(err, store.ErrNotFound) {
			writeError(w, http.StatusNotFound, "user not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "could not delete user")
		return
	}
	if err := s.rebuild(); err != nil {
		writeError(w, http.StatusInternalServerError, "could not apply server config")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Service) handleUserKey(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	u, err := s.store.Get(id)
	if err != nil {
		writeError(w, http.StatusNotFound, "user not found")
		return
	}
	if err := xray.ValidateHost(s.cfg); err != nil {
		writeError(w, http.StatusConflict, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"user":  u,
		"links": xray.BuildLinks(s.cfg, u),
	})
}
