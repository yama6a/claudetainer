#!/usr/bin/env bash
# SessionStart hook. Claude Code sources CLAUDE_ENV_FILE before every Bash command of this session only,
# so HOME, GOPATH and the kubeconfig set here stay inside the session's folder.
set -euo pipefail

SESSIONS=/workspace/sessions
SA=/var/run/secrets/kubernetes.io/serviceaccount
DEFAULT_NAMESPACE=claudetainer-scratch

[ -n "${CLAUDE_ENV_FILE:-}" ] || exit 0
cwd="$(jq -r '.cwd // empty')"
case "$cwd" in "$SESSIONS"/*) ;; *) exit 0 ;; esac

folder="$(printf '%s' "$cwd" | cut -d/ -f1-4)"
home="$folder/.home"
mkdir -p "$home/.kube"

# tokenFile, not an inline token: the projected ServiceAccount token rotates while the session runs.
if [ ! -f "$home/.kube/config" ]; then
  cat > "$home/.kube/config" << EOF
apiVersion: v1
kind: Config
clusters:
  - name: in-cluster
    cluster:
      server: https://kubernetes.default.svc
      certificate-authority: $SA/ca.crt
users:
  - name: claudetainer
    user:
      tokenFile: $SA/token
contexts:
  - name: in-cluster
    context:
      cluster: in-cluster
      user: claudetainer
      namespace: $DEFAULT_NAMESPACE
current-context: in-cluster
EOF
  chmod 0600 "$home/.kube/config"
fi

cat >> "$CLAUDE_ENV_FILE" << EOF
export HOME="$home"
export GOPATH="$home/go"
export KUBECONFIG="$home/.kube/config"
export PATH="$home/go/bin:$home/.local/bin:\$PATH"
EOF
