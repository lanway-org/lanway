package store

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

// ErrNotFound is returned when a user id does not exist.
var ErrNotFound = errors.New("user not found")

// User is a single VPN account on this server.
type User struct {
	ID          string    `json:"id"`           // UUIDv4, also the VLESS UUID
	Name        string    `json:"name"`         // human label, set by the manager
	ShortID     string    `json:"short_id"`     // REALITY per-user short id (hex)
	DataLimitGB float64   `json:"data_limit_gb"` // 0 = unlimited
	UsedBytes   int64     `json:"used_bytes"`   // cumulative usage
	CreatedAt   time.Time `json:"created_at"`
	Enabled     bool      `json:"enabled"`
}

// Store is a thread-safe, file-backed collection of users. All data lives on
// the operator's own server only — there is no central database.
type Store struct {
	mu   sync.RWMutex
	path string
	users map[string]*User
}

// Open loads the user store from dir, creating an empty one if absent.
func Open(dir string) (*Store, error) {
	s := &Store{
		path:  filepath.Join(dir, "users.json"),
		users: make(map[string]*User),
	}
	data, err := os.ReadFile(s.path)
	if err != nil {
		if os.IsNotExist(err) {
			return s, nil
		}
		return nil, fmt.Errorf("read users: %w", err)
	}
	var list []*User
	if err := json.Unmarshal(data, &list); err != nil {
		return nil, fmt.Errorf("parse users: %w", err)
	}
	for _, u := range list {
		s.users[u.ID] = u
	}
	return s, nil
}

// List returns all users ordered by creation time (newest first).
func (s *Store) List() []*User {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]*User, 0, len(s.users))
	for _, u := range s.users {
		cp := *u
		out = append(out, &cp)
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].CreatedAt.After(out[j].CreatedAt)
	})
	return out
}

// Get returns a copy of the user with the given id.
func (s *Store) Get(id string) (*User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	u, ok := s.users[id]
	if !ok {
		return nil, ErrNotFound
	}
	cp := *u
	return &cp, nil
}

// Create adds a new user with the given name and data limit (GB, 0 = unlimited).
func (s *Store) Create(name string, dataLimitGB float64) (*User, error) {
	id, err := newUUID()
	if err != nil {
		return nil, err
	}
	short, err := newShortID()
	if err != nil {
		return nil, err
	}
	u := &User{
		ID:          id,
		Name:        name,
		ShortID:     short,
		DataLimitGB: dataLimitGB,
		CreatedAt:   time.Now().UTC(),
		Enabled:     true,
	}
	s.mu.Lock()
	s.users[u.ID] = u
	err = s.persistLocked()
	s.mu.Unlock()
	if err != nil {
		return nil, err
	}
	cp := *u
	return &cp, nil
}

// Delete removes a user by id.
func (s *Store) Delete(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.users[id]; !ok {
		return ErrNotFound
	}
	delete(s.users, id)
	return s.persistLocked()
}

// SetUsage replaces a user's cumulative usage counter (called by the stats
// poller that reads Xray's traffic statistics).
func (s *Store) SetUsage(id string, usedBytes int64) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	u, ok := s.users[id]
	if !ok {
		return ErrNotFound
	}
	u.UsedBytes = usedBytes
	// Auto-disable when over the data limit so the next config rebuild drops them.
	if u.DataLimitGB > 0 && float64(u.UsedBytes) >= u.DataLimitGB*gib {
		u.Enabled = false
	}
	return s.persistLocked()
}

const gib = 1024 * 1024 * 1024

func (s *Store) persistLocked() error {
	list := make([]*User, 0, len(s.users))
	for _, u := range s.users {
		list = append(list, u)
	}
	data, err := json.MarshalIndent(list, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal users: %w", err)
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return fmt.Errorf("write users: %w", err)
	}
	return os.Rename(tmp, s.path)
}

// newUUID returns a random RFC 4122 version-4 UUID without external deps.
func newUUID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	b[6] = (b[6] & 0x0f) | 0x40 // version 4
	b[8] = (b[8] & 0x3f) | 0x80 // variant 10
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16]), nil
}

// newShortID returns an 8-character hex REALITY short id.
func newShortID() (string, error) {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return fmt.Sprintf("%x", b), nil
}
