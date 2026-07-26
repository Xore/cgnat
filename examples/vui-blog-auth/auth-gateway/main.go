// auth-gateway — a small reverse proxy that puts a login wall in front of an
// upstream web app. Nothing reaches the upstream until the visitor holds a
// valid session cookie.
//
// Flow:
//
//	request → gateway
//	  ├─ /_auth/*                 handled here (login page, submit, logout)
//	  ├─ valid session cookie     → reverse-proxied to UPSTREAM
//	  └─ no/invalid cookie        → 302 to /_auth/login?next=<path>
//
// The cookie is an HMAC-signed "expiry|signature" token — no server-side
// session store, so the gateway is stateless and horizontally scalable.
//
// This is deliberately dependency-free (stdlib only) so it compiles to a tiny
// static binary and is easy to audit.
package main

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

type config struct {
	listen     string
	upstream   *url.URL
	username   string
	password   string
	secret     []byte
	cookieName string
	ttl        time.Duration
	secure     bool
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func loadConfig(log *slog.Logger) config {
	upstreamRaw := getenv("UPSTREAM", "http://vui-blog:3000")
	up, err := url.Parse(upstreamRaw)
	if err != nil || up.Host == "" {
		log.Error("invalid UPSTREAM", "value", upstreamRaw, "error", err)
		os.Exit(1)
	}

	ttlHours, _ := strconv.Atoi(getenv("SESSION_TTL_HOURS", "12"))
	if ttlHours <= 0 {
		ttlHours = 12
	}

	// COOKIE_SECRET signs sessions. If unset we generate a random one, but then
	// sessions do not survive a restart — fine for a demo, warned about loudly.
	secretRaw := os.Getenv("COOKIE_SECRET")
	var secret []byte
	if secretRaw == "" {
		secret = make([]byte, 32)
		_, _ = rand.Read(secret)
		log.Warn("COOKIE_SECRET not set — generated a random key; sessions will not survive a restart")
	} else {
		secret = []byte(secretRaw)
	}

	return config{
		listen:     getenv("LISTEN_ADDR", ":8080"),
		upstream:   up,
		username:   getenv("AUTH_USERNAME", "admin"),
		password:   getenv("AUTH_PASSWORD", "change-me-gate"),
		secret:     secret,
		cookieName: getenv("COOKIE_NAME", "xore_gate"),
		ttl:        time.Duration(ttlHours) * time.Hour,
		secure:     getenv("COOKIE_SECURE", "true") != "false",
	}
}

/* ---------- session token ---------- */

// sign issues "exp|hmac(exp)" where exp is a unix-seconds expiry.
func (c config) sign() string {
	exp := strconv.FormatInt(time.Now().Add(c.ttl).Unix(), 10)
	mac := hmac.New(sha256.New, c.secret)
	mac.Write([]byte(exp))
	sig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	return exp + "|" + sig
}

// valid checks the HMAC and the expiry in constant time.
func (c config) valid(token string) bool {
	exp, sig, ok := strings.Cut(token, "|")
	if !ok {
		return false
	}
	mac := hmac.New(sha256.New, c.secret)
	mac.Write([]byte(exp))
	want := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	if subtle.ConstantTimeCompare([]byte(sig), []byte(want)) != 1 {
		return false
	}
	expUnix, err := strconv.ParseInt(exp, 10, 64)
	if err != nil {
		return false
	}
	return time.Now().Unix() < expUnix
}

/* ---------- brute-force throttle ---------- */

// A tiny per-IP failed-login limiter: 5 attempts, then a 5-minute lockout.
type throttle struct {
	mu       sync.Mutex
	fails    map[string]int
	lockedAt map[string]time.Time
}

func newThrottle() *throttle {
	return &throttle{fails: map[string]int{}, lockedAt: map[string]time.Time{}}
}

func (t *throttle) locked(ip string) bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	if until, ok := t.lockedAt[ip]; ok {
		if time.Now().Before(until.Add(5 * time.Minute)) {
			return true
		}
		delete(t.lockedAt, ip)
		delete(t.fails, ip)
	}
	return false
}

func (t *throttle) fail(ip string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.fails[ip]++
	if t.fails[ip] >= 5 {
		t.lockedAt[ip] = time.Now()
	}
}

func (t *throttle) reset(ip string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	delete(t.fails, ip)
	delete(t.lockedAt, ip)
}

func clientIP(r *http.Request) string {
	// Traefik/Cloudflare put the real client in X-Forwarded-For (first hop).
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		return strings.TrimSpace(strings.Split(xff, ",")[0])
	}
	host, _, _ := strings.Cut(r.RemoteAddr, ":")
	return host
}

// safeNext prevents open-redirects: only same-site absolute paths are allowed.
func safeNext(raw string) string {
	if raw == "" || !strings.HasPrefix(raw, "/") || strings.HasPrefix(raw, "//") {
		return "/"
	}
	return raw
}

/* ---------- HTTP ---------- */

type server struct {
	cfg   config
	log   *slog.Logger
	proxy *httputil.ReverseProxy
	tr    *throttle
}

func (s *server) setSession(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     s.cfg.cookieName,
		Value:    s.cfg.sign(),
		Path:     "/",
		HttpOnly: true,
		Secure:   s.cfg.secure,
		SameSite: http.SameSiteLaxMode,
		MaxAge:   int(s.cfg.ttl.Seconds()),
	})
}

func (s *server) clearSession(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     s.cfg.cookieName,
		Value:    "",
		Path:     "/",
		HttpOnly: true,
		Secure:   s.cfg.secure,
		SameSite: http.SameSiteLaxMode,
		MaxAge:   -1,
	})
}

func (s *server) authed(r *http.Request) bool {
	c, err := r.Cookie(s.cfg.cookieName)
	return err == nil && s.cfg.valid(c.Value)
}

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.URL.Path == "/_auth/health":
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
		return
	case r.URL.Path == "/_auth/login":
		s.handleLogin(w, r)
		return
	case r.URL.Path == "/_auth/logout":
		s.clearSession(w)
		http.Redirect(w, r, "/_auth/login", http.StatusSeeOther)
		return
	}

	if s.authed(r) {
		s.proxy.ServeHTTP(w, r)
		return
	}
	next := url.QueryEscape(r.URL.RequestURI())
	http.Redirect(w, r, "/_auth/login?next="+next, http.StatusSeeOther)
}

func (s *server) handleLogin(w http.ResponseWriter, r *http.Request) {
	next := safeNext(r.URL.Query().Get("next"))

	if r.Method == http.MethodGet {
		// Already signed in? Skip the form.
		if s.authed(r) {
			http.Redirect(w, r, next, http.StatusSeeOther)
			return
		}
		s.renderLogin(w, next, "")
		return
	}

	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "GET, POST")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	ip := clientIP(r)
	if s.tr.locked(ip) {
		s.log.Warn("login locked out", "ip", ip)
		s.renderLogin(w, next, "too many attempts — try again in a few minutes")
		return
	}

	if err := r.ParseForm(); err != nil {
		s.renderLogin(w, next, "bad form submission")
		return
	}
	user := r.PostForm.Get("username")
	pass := r.PostForm.Get("password")

	userOK := subtle.ConstantTimeCompare([]byte(user), []byte(s.cfg.username)) == 1
	passOK := subtle.ConstantTimeCompare([]byte(pass), []byte(s.cfg.password)) == 1
	if !userOK || !passOK {
		s.tr.fail(ip)
		s.log.Warn("login failed", "ip", ip, "user", user)
		s.renderLogin(w, next, "invalid credentials")
		return
	}

	s.tr.reset(ip)
	s.setSession(w)
	s.log.Info("login ok", "ip", ip, "user", user)
	http.Redirect(w, r, next, http.StatusSeeOther)
}

func (s *server) renderLogin(w http.ResponseWriter, next, errMsg string) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	// Failed logins should not be cached.
	w.Header().Set("Cache-Control", "no-store")
	errHTML := ""
	if errMsg != "" {
		errHTML = `<p class="err">` + htmlEscape(errMsg) + `</p>`
	}
	page := strings.ReplaceAll(loginPage, "{{NEXT}}", htmlEscape(next))
	page = strings.ReplaceAll(page, "{{ERROR}}", errHTML)
	_, _ = w.Write([]byte(page))
}

func htmlEscape(s string) string {
	r := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;", "'", "&#39;")
	return r.Replace(s)
}

func main() {
	// Self-healthcheck mode for the scratch image's Docker HEALTHCHECK
	// (no shell/wget available). Probes the unauthenticated /_auth/health.
	if len(os.Args) > 1 && os.Args[1] == "-healthcheck" {
		addr := getenv("LISTEN_ADDR", ":8080")
		if strings.HasPrefix(addr, ":") {
			addr = "127.0.0.1" + addr
		}
		client := http.Client{Timeout: 3 * time.Second}
		resp, err := client.Get("http://" + addr + "/_auth/health")
		if err != nil || resp.StatusCode != http.StatusOK {
			os.Exit(1)
		}
		os.Exit(0)
	}

	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg := loadConfig(log)

	proxy := httputil.NewSingleHostReverseProxy(cfg.upstream)
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		log.Error("upstream error", "error", err)
		http.Error(w, "upstream unavailable", http.StatusBadGateway)
	}

	s := &server{cfg: cfg, log: log, proxy: proxy, tr: newThrottle()}

	// A stable fingerprint of the secret so operators can confirm all replicas
	// share the same COOKIE_SECRET without logging the secret itself.
	sum := sha256.Sum256(cfg.secret)
	log.Info("auth-gateway starting",
		"listen", cfg.listen,
		"upstream", cfg.upstream.String(),
		"ttl", cfg.ttl.String(),
		"secret_fp", hex.EncodeToString(sum[:4]),
	)

	srv := &http.Server{
		Addr:              cfg.listen,
		Handler:           s,
		ReadHeaderTimeout: 5 * time.Second,
	}
	if err := srv.ListenAndServe(); err != nil {
		log.Error("server stopped", "error", err)
		os.Exit(1)
	}
}
