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
    phpv() {
      MISE_PHP_VERSION=$1 php -d zend_extension=xdebug -d extension=pcov -r "
        \$m = array_filter([\"pdo_pgsql\", \"pdo_sqlite\", \"pdo_mysql\", \"intl\", \"gd\", \"zip\", \"sodium\", \"gmp\",
          \"bz2\", \"mbstring\", \"curl\", \"openssl\", \"readline\"], fn (\$e) => !extension_loaded(\$e));
        echo PHP_VERSION, \" \", phpversion(\"xdebug\"), \" \", phpversion(\"pcov\"), \" \",
          \$m ? \"missing:\" . implode(\",\", \$m) : \"ext-ok\";"
    }
    phpini() { php -r "echo ini_get(\"$1\");"; }
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
    p mise "mise --version"
    p php-path "command -v php"
    p php-default "php -v"
    p php82 "phpv 8.2"
    p php83 "phpv 8.3"
    p php84 "phpv 8.4"
    p php85 "phpv 8.5"
    p php-memory "phpini memory_limit"
    p composer "composer --version"
    p intelephense "command -v intelephense && jq -r .version /opt/intelephense/node_modules/intelephense/package.json"
    p php-lsp-plugin "jq -r .plugins[].name /opt/claudetainer-plugins/.claude-plugin/marketplace.json"
    p shellcheck "shellcheck --version"
    p shfmt "shfmt --version"
    p actionlint "actionlint --version"
    p hadolint "hadolint --version"
    p yamllint "yamllint --version"
    p prettier "prettier --version"
    p renovate "renovate --version"
    p renovate-config-validator "command -v renovate-config-validator"
    p uvx "uvx --help"
    p dlv "dlv version"
    p file "file --version"
    p sqlite3 "sqlite3 --version"
    p zip "zip -v"
    p wget "wget --version"
    p mcp-victoriametrics "go version -m /usr/local/bin/mcp-victoriametrics"
    p mcp-victorialogs "go version -m /usr/local/bin/mcp-victorialogs"
    p mcp-victoriametrics-run "mcp-victoriametrics"
    p mcp-victorialogs-run "mcp-victorialogs"
    p plugins "jq -r .plugins[].name /opt/claudetainer-plugins/.claude-plugin/marketplace.json"
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
expect mise "$(arg MISE_VERSION | sed 's/^v//') "
expect php-path /opt/mise/shims/php
expect php-default "PHP $(arg PHP85_VERSION) "
pcov="$(arg PCOV_VERSION | sed 's/^v//')"
expect php82 "$(arg PHP82_VERSION) $(arg XDEBUG_VERSION) $pcov ext-ok"
expect php83 "$(arg PHP83_VERSION) $(arg XDEBUG_VERSION) $pcov ext-ok"
expect php84 "$(arg PHP84_VERSION) $(arg XDEBUG_VERSION) $pcov ext-ok"
expect php85 "$(arg PHP85_VERSION) $(arg XDEBUG_VERSION) $pcov ext-ok"
expect php-memory 1G
expect composer "Composer version $(arg COMPOSER_VERSION) "
expect intelephense "$(arg INTELEPHENSE_VERSION)"
expect php-lsp-plugin php-lsp
expect shellcheck "version: $(arg SHELLCHECK_VERSION | sed 's/^v//')"
expect shfmt "$(arg SHFMT_VERSION)"
expect actionlint "$(arg ACTIONLINT_VERSION | sed 's/^v//')"
expect hadolint "Linter $(arg HADOLINT_VERSION | sed 's/^v//')"
expect yamllint "yamllint $(arg YAMLLINT_VERSION)"
expect prettier "$(arg PRETTIER_VERSION)"
expect renovate "$(arg RENOVATE_VERSION)"
expect renovate-config-validator /usr/local/bin/renovate-config-validator
expect uvx "Run a command provided by a Python package"
expect dlv "Version: $(arg DELVE_VERSION | sed 's/^v//')"
expect file "file-"
expect sqlite3 "3."
expect zip "This is Zip"
expect wget "GNU Wget"
expect mcp-victoriametrics "mcp-victoriametrics $(arg MCP_VICTORIAMETRICS_VERSION)"
expect mcp-victorialogs "mcp-victorialogs $(arg MCP_VICTORIALOGS_VERSION)"
expect mcp-victoriametrics-run "VM_INSTANCE_ENTRYPOINT or VMC_API_KEY is not set"
expect mcp-victorialogs-run "VL_INSTANCE_ENTRYPOINT is not set"
expect plugins "playwright victoriametrics victorialogs"
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
