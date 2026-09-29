// Command login-exporter serves the expiry of the Claude login on the config volume as Prometheus metrics.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"go.uber.org/zap"
)

const (
	listenAddr        = ":9100"
	defaultConfigDir  = "/home/agent/.claude"
	credentialsFile   = ".credentials.json"
	readHeaderTimeout = 5 * time.Second
	shutdownTimeout   = 5 * time.Second
	millisPerSecond   = 1000
)

type credentials struct {
	ClaudeAiOauth *struct {
		ExpiresAt             int64 `json:"expiresAt"`
		RefreshTokenExpiresAt int64 `json:"refreshTokenExpiresAt"`
	} `json:"claudeAiOauth"`
}

// login holds both expiries in Unix seconds. A missing login keeps them at 0, which reads as long expired, so
// the expiry alert fires for it too.
type login struct {
	present       bool
	refreshExpiry int64
	accessExpiry  int64
}

func readLogin(path string, logger *zap.Logger) login {
	raw, err := os.ReadFile(path)
	if err != nil {
		if !errors.Is(err, fs.ErrNotExist) {
			logger.Warn("read credentials", zap.String("path", path), zap.Error(err))
		}

		return login{}
	}

	var c credentials
	if err := json.Unmarshal(raw, &c); err != nil || c.ClaudeAiOauth == nil {
		logger.Warn("parse credentials", zap.String("path", path), zap.Error(err))

		return login{}
	}

	// Claude Code stores both expiries in milliseconds.
	return login{
		present:       true,
		refreshExpiry: c.ClaudeAiOauth.RefreshTokenExpiresAt / millisPerSecond,
		accessExpiry:  c.ClaudeAiOauth.ExpiresAt / millisPerSecond,
	}
}

func writeMetrics(w io.Writer, l login) error {
	present := 0
	if l.present {
		present = 1
	}

	_, err := fmt.Fprintf(w, `# HELP claudetainer_login_present 1 when a readable claude.ai login exists on the config volume.
# TYPE claudetainer_login_present gauge
claudetainer_login_present %d
# HELP claudetainer_login_refresh_token_expiry_timestamp_seconds When the login stops working unless a new one is sealed.
# TYPE claudetainer_login_refresh_token_expiry_timestamp_seconds gauge
claudetainer_login_refresh_token_expiry_timestamp_seconds %d
# HELP claudetainer_login_access_token_expiry_timestamp_seconds When Claude Code next refreshes the access token.
# TYPE claudetainer_login_access_token_expiry_timestamp_seconds gauge
claudetainer_login_access_token_expiry_timestamp_seconds %d
`, present, l.refreshExpiry, l.accessExpiry)
	if err != nil {
		return fmt.Errorf("write metrics: %w", err)
	}

	return nil
}

type metricsHandler struct {
	path   string
	logger *zap.Logger
}

func (h metricsHandler) ServeHTTP(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")

	if err := writeMetrics(w, readLogin(h.path, h.logger)); err != nil {
		h.logger.Warn("serve metrics", zap.Error(err))
	}
}

func run(ctx context.Context, logger *zap.Logger) error {
	dir := os.Getenv("CLAUDE_CONFIG_DIR")
	if dir == "" {
		dir = defaultConfigDir
	}

	mux := http.NewServeMux()
	mux.Handle("GET /metrics", metricsHandler{path: filepath.Join(dir, credentialsFile), logger: logger})

	srv := &http.Server{Addr: listenAddr, Handler: mux, ReadHeaderTimeout: readHeaderTimeout}
	serveErr := make(chan error, 1)

	go func() { serveErr <- srv.ListenAndServe() }()

	select {
	case err := <-serveErr:
		return fmt.Errorf("serve: %w", err)
	case <-ctx.Done():
	}

	shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), shutdownTimeout)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("shutdown: %w", err)
	}

	return nil
}

func main() {
	logger, err := zap.NewProduction()
	if err != nil {
		panic(err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()

	if err := run(ctx, logger); err != nil {
		logger.Fatal("login-exporter stopped", zap.Error(err))
	}
}
