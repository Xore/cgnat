// go-api — stdlib-only blog backend serving the shared xore//blog frontend.
//
// Same API contract as every blog example in cgnat/examples:
//   public:  GET /api/posts, GET /api/posts/{id}, GET /health
//   admin:   POST /api/admin/login + CRUD under /api/admin/posts,
//            guarded by the X-Admin-Token header (ADMIN_PASSWORD env)
//
// Features:
//   - Frontend embedded into the binary (go:embed) — scratch image, no files
//   - JSON file persistence (DATA_FILE, atomic replace on save)
//   - JSON structured logging (log/slog) with a request-logging middleware
//   - Graceful shutdown on SIGTERM/SIGINT
//   - Self-healthcheck mode (`/server -healthcheck`) — no shell/wget in scratch
package main

import (
	"context"
	"crypto/rand"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

//go:embed static
var staticFiles embed.FS

type Post struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Slug      string `json:"slug"`
	Content   string `json:"content"`
	Published bool   `json:"published"`
	CreatedAt int64  `json:"createdAt"`
	UpdatedAt int64  `json:"updatedAt"`
}

type store struct {
	mu    sync.RWMutex
	posts []Post
	file  string
	log   *slog.Logger
}

func nowMs() int64 { return time.Now().UnixMilli() }

func newID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

var slugRe = regexp.MustCompile(`[^a-z0-9]+`)

func slugify(title string) string {
	return strings.Trim(slugRe.ReplaceAllString(strings.ToLower(title), "-"), "-")
}

func newStore(file string, log *slog.Logger) *store {
	s := &store{file: file, log: log}
	if raw, err := os.ReadFile(file); err == nil {
		_ = json.Unmarshal(raw, &s.posts)
	}
	if len(s.posts) == 0 {
		now := nowMs()
		s.posts = []Post{{
			ID:    newID(),
			Title: "Welcome to the Go blog",
			Slug:  "welcome-to-the-go-blog",
			Content: "This blog runs behind a CGNAT VPS gateway — self-hosted, no open ports, " +
				"zero-trust.\n\nBackend: Go stdlib (net/http), storage: JSON file, frontend " +
				"embedded into a single static binary in a scratch image.\n\n" +
				"Edit or delete this post from the admin panel.",
			Published: true,
			CreatedAt: now,
			UpdatedAt: now,
		}}
		s.save()
	}
	return s
}

// save writes posts.json atomically; callers must hold mu
func (s *store) save() {
	data, _ := json.MarshalIndent(s.posts, "", "  ")
	_ = os.MkdirAll(filepath.Dir(s.file), 0o755)
	tmp := s.file + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		s.log.Warn("persist failed", "error", err)
		return
	}
	if err := os.Rename(tmp, s.file); err != nil {
		s.log.Warn("persist failed", "error", err)
	}
}

func (s *store) sorted(publishedOnly bool) []Post {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Post, 0, len(s.posts))
	for _, p := range s.posts {
		if !publishedOnly || p.Published {
			out = append(out, p)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt > out[j].CreatedAt })
	return out
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// logging + panic-recovery middleware
func wrap(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		defer func() {
			if rec := recover(); rec != nil {
				log.Error("panic", "path", r.URL.Path, "error", fmt.Sprint(rec))
				writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal server error"})
			}
		}()
		next.ServeHTTP(w, r)
		log.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"remote", r.RemoteAddr,
			"duration_ms", time.Since(start).Milliseconds(),
		)
	})
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "5003"
	}
	secret := os.Getenv("ADMIN_PASSWORD")
	if secret == "" {
		secret = "change-me-go"
	}
	dataFile := os.Getenv("DATA_FILE")
	if dataFile == "" {
		dataFile = "/data/posts.json"
	}

	// Healthcheck mode: used as the Docker HEALTHCHECK command inside
	// the scratch image (no shell available).
	healthcheck := flag.Bool("healthcheck", false, "probe /health and exit")
	flag.Parse()
	if *healthcheck {
		client := http.Client{Timeout: 3 * time.Second}
		resp, err := client.Get("http://127.0.0.1:" + port + "/health")
		if err != nil || resp.StatusCode != http.StatusOK {
			os.Exit(1)
		}
		os.Exit(0)
	}

	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	blog := newStore(dataFile, log)

	authorized := func(r *http.Request) bool {
		return r.Header.Get("X-Admin-Token") == secret
	}

	mux := http.NewServeMux()

	// Embedded frontend (index.html, app.js, xore.css)
	staticFS, _ := fs.Sub(staticFiles, "static")
	mux.Handle("GET /", http.FileServerFS(staticFS))

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		blog.mu.RLock()
		count := len(blog.posts)
		blog.mu.RUnlock()
		writeJSON(w, http.StatusOK, map[string]any{"status": "ok", "posts": count})
	})

	mux.HandleFunc("POST /api/admin/login", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Password string `json:"password"`
		}
		_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&body)
		if body.Password != secret {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "Invalid password"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "token": secret})
	})

	mux.HandleFunc("GET /api/posts", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, blog.sorted(true))
	})

	mux.HandleFunc("GET /api/posts/{id}", func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		blog.mu.RLock()
		defer blog.mu.RUnlock()
		for _, p := range blog.posts {
			if p.ID == id && p.Published {
				writeJSON(w, http.StatusOK, p)
				return
			}
		}
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Not found"})
	})

	mux.HandleFunc("GET /api/admin/posts", func(w http.ResponseWriter, r *http.Request) {
		if !authorized(r) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "Unauthorized"})
			return
		}
		writeJSON(w, http.StatusOK, blog.sorted(false))
	})

	type postInput struct {
		Title     *string `json:"title"`
		Slug      *string `json:"slug"`
		Content   *string `json:"content"`
		Published *bool   `json:"published"`
	}

	mux.HandleFunc("POST /api/admin/posts", func(w http.ResponseWriter, r *http.Request) {
		if !authorized(r) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "Unauthorized"})
			return
		}
		var in postInput
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&in); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
			return
		}
		title := ""
		if in.Title != nil {
			title = strings.TrimSpace(*in.Title)
		}
		content := ""
		if in.Content != nil {
			content = *in.Content
		}
		if title == "" || strings.TrimSpace(content) == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "title and content required"})
			return
		}
		slug := ""
		if in.Slug != nil {
			slug = strings.TrimSpace(*in.Slug)
		}
		if slug == "" {
			slug = slugify(title)
		}
		now := nowMs()
		post := Post{
			ID: newID(), Title: title, Slug: slug, Content: content,
			Published: in.Published != nil && *in.Published,
			CreatedAt: now, UpdatedAt: now,
		}
		blog.mu.Lock()
		blog.posts = append(blog.posts, post)
		blog.save()
		blog.mu.Unlock()
		writeJSON(w, http.StatusCreated, post)
	})

	mux.HandleFunc("PUT /api/admin/posts/{id}", func(w http.ResponseWriter, r *http.Request) {
		if !authorized(r) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "Unauthorized"})
			return
		}
		var in postInput
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&in); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
			return
		}
		id := r.PathValue("id")
		blog.mu.Lock()
		defer blog.mu.Unlock()
		for i := range blog.posts {
			if blog.posts[i].ID != id {
				continue
			}
			p := &blog.posts[i]
			if in.Title != nil {
				p.Title = strings.TrimSpace(*in.Title)
			}
			if in.Slug != nil {
				p.Slug = strings.TrimSpace(*in.Slug)
			}
			if in.Content != nil {
				p.Content = *in.Content
			}
			if in.Published != nil {
				p.Published = *in.Published
			}
			p.UpdatedAt = nowMs()
			blog.save()
			writeJSON(w, http.StatusOK, *p)
			return
		}
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Not found"})
	})

	mux.HandleFunc("DELETE /api/admin/posts/{id}", func(w http.ResponseWriter, r *http.Request) {
		if !authorized(r) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "Unauthorized"})
			return
		}
		id := r.PathValue("id")
		blog.mu.Lock()
		defer blog.mu.Unlock()
		for i := range blog.posts {
			if blog.posts[i].ID == id {
				blog.posts = append(blog.posts[:i], blog.posts[i+1:]...)
				blog.save()
				w.WriteHeader(http.StatusNoContent)
				return
			}
		}
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Not found"})
	})

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           wrap(log, mux),
		ReadHeaderTimeout: 5 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	go func() {
		log.Info("listening", "port", port, "data", dataFile)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	// Block until SIGTERM/SIGINT, then drain connections for up to 10s
	<-ctx.Done()
	log.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Error("shutdown error", "error", err)
	}
	log.Info("stopped")
}
