package main

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
	"go.uber.org/zap"
)

func TestReadLogin_Files(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		content *string
		want    login
	}{
		{
			name:    "valid login",
			content: ptr(`{"claudeAiOauth":{"expiresAt":1790000000123,"refreshTokenExpiresAt":1792000000999}}`),
			want:    login{present: true, refreshExpiry: 1792000000, accessExpiry: 1790000000},
		},
		{name: "missing file", content: nil, want: login{}},
		{name: "broken json", content: ptr(`{"claudeAiOauth":`), want: login{}},
		{name: "api key login without oauth", content: ptr(`{}`), want: login{}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			path := filepath.Join(t.TempDir(), credentialsFile)
			if tt.content != nil {
				require.NoError(t, os.WriteFile(path, []byte(*tt.content), 0o600))
			}

			require.Equal(t, tt.want, readLogin(path, zap.NewNop()))
		})
	}
}

func TestWriteMetrics_Values(t *testing.T) {
	t.Parallel()

	var out bytes.Buffer
	require.NoError(t, writeMetrics(&out, login{present: true, refreshExpiry: 1792000000, accessExpiry: 1790000000}))

	require.Contains(t, out.String(), "\nclaudetainer_login_present 1\n")
	require.Contains(t, out.String(), "\nclaudetainer_login_refresh_token_expiry_timestamp_seconds 1792000000\n")
	require.Contains(t, out.String(), "\nclaudetainer_login_access_token_expiry_timestamp_seconds 1790000000\n")
}

func ptr(s string) *string { return &s }
