package api

import (
	"context"
	"log"
	"sync"
	"time"

	"github.com/lanway-org/lanway/server/internal/config"
	"github.com/lanway-org/lanway/server/internal/store"
	"github.com/lanway-org/lanway/server/internal/xray"
)

// Service ties together configuration, the user store and the Xray core. It is
// the single source of truth the HTTP handlers operate on.
type Service struct {
	cfg       *config.Config
	configDir string
	store     *store.Store
	runner    *xray.Runner

	mu sync.Mutex // serialises config rebuilds
}

// NewService constructs the service and applies the initial Xray config.
func NewService(cfg *config.Config, configDir string, st *store.Store, runner *xray.Runner) (*Service, error) {
	s := &Service{cfg: cfg, configDir: configDir, store: st, runner: runner}
	if err := s.rebuild(); err != nil {
		return nil, err
	}
	return s, nil
}

// rebuild regenerates the Xray config from the current user set and restarts
// the core. Callers that mutate users must call this afterwards.
func (s *Service) rebuild() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.runner.Apply(s.cfg, s.store.List())
}

// StartUsagePoller periodically reads per-user traffic from Xray and persists
// it, auto-disabling users who exceed their limit. It runs until ctx is done.
func (s *Service) StartUsagePoller(ctx context.Context, every time.Duration) {
	ticker := time.NewTicker(every)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.pollUsage(ctx)
		}
	}
}

func (s *Service) pollUsage(ctx context.Context) {
	if res := s.PollNow(ctx); res.Error != "" {
		log.Printf("usage poll: %s", res.Error)
	}
}

// PollResult summarises one usage poll, for the dashboard's "refresh now" so an
// operator can immediately see whether traffic accounting is working.
type PollResult struct {
	StatEntries int    `json:"stat_entries"` // how many user stats Xray returned
	TotalBytes  int64  `json:"total_bytes"`  // sum across users after this poll
	Error       string `json:"error,omitempty"`
}

// PollNow reads per-user traffic from Xray right now, persists it, auto-disables
// over-limit users, and returns a short diagnostic. Safe to call on demand.
func (s *Service) PollNow(ctx context.Context) PollResult {
	usage, err := s.runner.QueryUsage(ctx)
	if err != nil {
		return PollResult{Error: err.Error()}
	}
	var limitHit bool
	for id, bytes := range usage {
		before, err := s.store.Get(id)
		if err != nil {
			continue
		}
		if err := s.store.SetUsage(id, bytes); err != nil {
			log.Printf("usage persist %s: %v", id, err)
			continue
		}
		after, err := s.store.Get(id)
		if err == nil && before.Enabled && !after.Enabled {
			limitHit = true // a user just crossed their data limit
		}
	}
	// If anyone was auto-disabled, rebuild so the core drops them.
	if limitHit {
		if err := s.rebuild(); err != nil {
			log.Printf("rebuild after limit: %v", err)
		}
	}
	var total int64
	for _, u := range s.store.List() {
		total += u.UsedBytes
	}
	return PollResult{StatEntries: len(usage), TotalBytes: total}
}
