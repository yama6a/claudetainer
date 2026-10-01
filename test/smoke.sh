#!/usr/bin/env bash
# Checks a built image: every pinned tool answers with the version its Dockerfile ARG pins, from the expected path.
set -uo pipefail

image="${1:?usage: test/smoke.sh <image>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
arg() { sed -n "s/^ARG $1=//p" "$root/Dockerfile"; }

# One container run for all probes. Each line is `name<TAB>output`.
probes="$(
  docker run --rm --entrypoint bash "$image" -c '
    p() { printf "%s\t%s\n" "$1" "$(eval "$2" 2>&1 | tr "\n\t" "  ")"; }
    p claude "claude --version"
    p kubectl "kubectl version --client"
    p helm "helm version --short"
    p k9s "k9s version --short"
    p kustomize "kustomize version"
    p kubectx "kubectx --version"
    p kubens "kubens --version"
    p kubeconform "kubeconform -v"
    p yq "yq --version"
    p talosctl "talosctl version --client --short"
    p golangci-lint "golangci-lint --version"
    p go "go version"
    p go-path "command -v go"
    p gopls "gopls version"
    p oapi-codegen "oapi-codegen --version"
    p gofumpt "gofumpt --version"
    p govulncheck "govulncheck -version"
    p node "node --version"
    p node-path "command -v node"
    p nvm ". /opt/nvm/nvm.sh --no-use && nvm --version"
    p nvm-ls ". /opt/nvm/nvm.sh --no-use && nvm ls --no-colors"
    p psql "psql --version"
    p pgcli "pgcli --version"
    p python3 "python3 --version"
    p gcc "gcc --version"
    p playwright-mcp "playwright-mcp --version"
    p chromium "ls /opt/ms-playwright"
    p perl "perl -CSD -e \"exit(q(\\x{e4}) =~ /\\p{L}/ ? 0 : 1)\" && echo unicode-ok"
    p grep-p "echo abc | grep -P \"b(?=c)\""
    p sudo "command -v sudo || echo absent"
    p marketplace "jq -r .name /opt/claudetainer-plugins/.claude-plugin/marketplace.json"
    p playwright-plugin "jq -r .playwright.command /opt/claudetainer-plugins/external_plugins/playwright/.mcp.json"
    p context7-plugin "jq -r .mcpServers.context7.headersHelper /opt/claudetainer-plugins/external_plugins/context7/.mcp.json"
    p context7-headers "/usr/local/lib/claudetainer/context7-headers.sh"
    p scheduled-session "/usr/local/lib/claudetainer/scheduled-session.sh Bad < /dev/null 2>&1 || true"
    p login-exporter "(login-exporter > /dev/null 2>&1 &) && sleep 1 && curl -fsS localhost:9100/metrics | grep ^claudetainer_login_present"
    p uid "id -u"
    p bash-env "echo \"[${BASH_ENV}]\""
  '
)" || {
  echo "FAIL: could not run $image"
  exit 1
}

fail=0
expect() {
  local name=$1 want=$2 got
  got="$(awk -F '\t' -v n="$name" '$1 == n { print $2 }' <<< "$probes")"
  if [[ "$got" == *"$want"* ]]; then
    echo "ok    $name"
  else
    echo "FAIL  $name: want '$want', got '$got'"
    fail=1
  fi
}

expect claude "$(arg CLAUDE_VERSION)"
expect kubectl "$(arg KUBECTL_VERSION)"
expect helm "$(arg HELM_VERSION)"
expect k9s "$(arg K9S_VERSION)"
expect kustomize "$(arg KUSTOMIZE_VERSION)"
expect kubectx "$(arg KUBECTX_VERSION | sed 's/^v//')"
expect kubens "$(arg KUBECTX_VERSION | sed 's/^v//')"
expect kubeconform "$(arg KUBECONFORM_VERSION)"
expect yq "$(arg YQ_VERSION)"
expect talosctl "$(arg TALOSCTL_VERSION)"
expect golangci-lint "$(arg GOLANGCI_LINT_VERSION)"
expect go "$(arg GO_VERSION) "
expect go-path /usr/local/go/bin/go
expect gopls "$(arg GOPLS_VERSION)"
expect oapi-codegen "$(arg OAPI_CODEGEN_VERSION)"
expect gofumpt "$(arg GOFUMPT_VERSION)"
expect govulncheck "$(arg GOVULNCHECK_VERSION)"
expect node "$(arg NODE26_VERSION)"
expect node-path /opt/nvm/current/bin/node
expect nvm "$(arg NVM_VERSION | sed 's/^v//')"
expect nvm-ls "$(arg NODE24_VERSION)"
expect psql " $(arg PG_MAJOR)."
expect pgcli "$(arg PGCLI_VERSION)"
expect python3 "Python 3."
expect gcc "gcc"
expect playwright-mcp "$(arg PLAYWRIGHT_MCP_VERSION)"
expect chromium chromium
expect perl unicode-ok
expect grep-p abc
expect sudo absent
expect marketplace claudetainer-plugins
expect playwright-plugin playwright-mcp
expect context7-plugin /usr/local/lib/claudetainer/context7-headers.sh
expect context7-headers "{}"
expect scheduled-session "usage: scheduled-session.sh"
expect login-exporter "claudetainer_login_present 0"
expect uid 1000
expect bash-env "[]"

exit "$fail"
