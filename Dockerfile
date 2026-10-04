# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e

# Global scope. Redeclare each ARG bare above the RUN that uses it, so a bump rebuilds from there down.
# renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CLAUDE_VERSION=2.1.289
# renovate: datasource=git-refs depName=https://github.com/anthropics/claude-plugins-official branch=main
ARG CLAUDE_PLUGINS_REF=d182ca456ca09d31d139f7d3818d1d333b103cce
# renovate: datasource=npm depName=@playwright/mcp
ARG PLAYWRIGHT_MCP_VERSION=0.0.83
# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=v1.37.1
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION=v4.3.0
# renovate: datasource=github-releases depName=derailed/k9s
ARG K9S_VERSION=v0.51.0
# renovate: datasource=github-releases depName=kubernetes-sigs/kustomize
ARG KUSTOMIZE_VERSION=v5.8.2
# renovate: datasource=github-releases depName=ahmetb/kubectx
ARG KUBECTX_VERSION=v0.11.0
# renovate: datasource=github-releases depName=yannh/kubeconform
ARG KUBECONFORM_VERSION=v0.8.0
# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION=v4.54.1
# renovate: datasource=github-releases depName=siderolabs/talos
ARG TALOSCTL_VERSION=v1.14.2
# renovate: datasource=github-releases depName=golangci/golangci-lint
ARG GOLANGCI_LINT_VERSION=2.14.0
# renovate: datasource=github-tags depName=golang/go versioning=regex:^go(?<major>\d+)\.(?<minor>\d+)(\.(?<patch>\d+))?$
ARG GO_VERSION=go1.27.1
# renovate: datasource=go depName=golang.org/x/tools/gopls
ARG GOPLS_VERSION=v0.23.0
# renovate: datasource=go depName=github.com/oapi-codegen/oapi-codegen/v2
ARG OAPI_CODEGEN_VERSION=v2.8.0
# renovate: datasource=go depName=mvdan.cc/gofumpt
ARG GOFUMPT_VERSION=v0.12.0
# renovate: datasource=go depName=golang.org/x/vuln
ARG GOVULNCHECK_VERSION=v1.8.0
# renovate: datasource=github-releases depName=nvm-sh/nvm
ARG NVM_VERSION=v0.40.8
# renovate: datasource=github-tags depName=nodejs/node
ARG NODE24_VERSION=v24.21.0
# renovate: datasource=github-tags depName=nodejs/node
ARG NODE26_VERSION=v26.10.0
# renovate: datasource=pypi depName=pgcli
ARG PGCLI_VERSION=4.7.1
ARG PG_MAJOR=18

# Cross-compiles on the build machine's architecture, so this stage needs no emulation.
FROM --platform=$BUILDPLATFORM golang:1.27-alpine@sha256:8a5910f31396cd4d89662f56c68b3ae31d374308270a1c3bd96672ee5ed43414 AS exporter
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd/ cmd/
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -trimpath -ldflags='-s -w' -o /login-exporter ./cmd/login-exporter

FROM docker/sandbox-templates:claude-code-minimal-0.7.0@sha256:31176d2cbb07ba18a709f015bea0e6e3c56f6b7b92744d16309d94e905c91482

ARG TARGETARCH
USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# The sandbox template is built for one agent per container. Every session here shares one pod, so drop
# its passwordless sudo, the env file every shell sources, the global npm prefix and its unpinned Claude.
# sudo refuses its own removal while root has no password, which is normal in an image.
RUN SUDO_FORCE_REMOVE=yes apt-get purge -y sudo \
    && rm -rf /etc/sudoers.d /etc/sandbox-persistent.sh /etc/profile.d/sandbox-persistent.sh \
      /usr/local/share/npm-global /home/agent/.local/bin/claude /home/agent/.local/share/claude \
      /home/agent/.claude /home/agent/.claude.json /home/agent/.docker \
    && gpasswd -d agent docker \
    && sed -i '/Docker Sandbox/,/^export BASH_ENV/d' /etc/bash.bashrc

ARG PG_MAJOR
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential gnupg perl pkg-config python3 \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc -o /etc/apt/keyrings/postgresql.asc \
    && echo "deb [arch=${TARGETARCH} signed-by=/etc/apt/keyrings/postgresql.asc] https://apt.postgresql.org/pub/repos/apt $(sed -n "s/^VERSION_CODENAME=//p" /etc/os-release)-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends "postgresql-client-${PG_MAJOR}" \
    && rm -rf /var/lib/apt/lists/*

# kubectx ships x86_64 where the rest ship amd64.
ARG KUBECTL_VERSION
ARG HELM_VERSION
ARG K9S_VERSION
ARG KUSTOMIZE_VERSION
ARG KUBECTX_VERSION
ARG KUBECONFORM_VERSION
ARG YQ_VERSION
ARG TALOSCTL_VERSION
ARG GOLANGCI_LINT_VERSION
ARG GO_VERSION
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) alt_arch=x86_64 ;; \
      arm64) alt_arch=arm64 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"; \
    curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${TARGETARCH}"; \
    curl -fsSL -o /usr/local/bin/talosctl "https://github.com/siderolabs/talos/releases/download/${TALOSCTL_VERSION}/talosctl-linux-${TARGETARCH}"; \
    chmod 0755 /usr/local/bin/kubectl /usr/local/bin/yq /usr/local/bin/talosctl; \
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" | tar -xz -C /tmp "linux-${TARGETARCH}/helm"; \
    install -m 0755 "/tmp/linux-${TARGETARCH}/helm" /usr/local/bin/helm; \
    curl -fsSL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${TARGETARCH}.tar.gz" | tar -xz -C /tmp k9s; \
    curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz" | tar -xz -C /tmp kustomize; \
    curl -fsSL "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-${TARGETARCH}.tar.gz" | tar -xz -C /tmp kubeconform; \
    curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubectx_${KUBECTX_VERSION}_linux_${alt_arch}.tar.gz" | tar -xz -C /tmp kubectx; \
    curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubens_${KUBECTX_VERSION}_linux_${alt_arch}.tar.gz" | tar -xz -C /tmp kubens; \
    install -m 0755 /tmp/k9s /tmp/kustomize /tmp/kubeconform /tmp/kubectx /tmp/kubens /usr/local/bin/; \
    curl -fsSL "https://github.com/golangci/golangci-lint/releases/download/v${GOLANGCI_LINT_VERSION}/golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${TARGETARCH}.tar.gz" \
      | tar -xz -C /tmp "golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${TARGETARCH}/golangci-lint"; \
    install -m 0755 "/tmp/golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${TARGETARCH}/golangci-lint" /usr/local/bin/golangci-lint; \
    curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-${TARGETARCH}.tar.gz" | tar -xz -C /usr/local; \
    rm -rf /tmp/*

ARG GOPLS_VERSION
ARG OAPI_CODEGEN_VERSION
ARG GOFUMPT_VERSION
ARG GOVULNCHECK_VERSION
RUN export PATH="/usr/local/go/bin:${PATH}" GOFLAGS=-trimpath GOBIN=/usr/local/bin GOPATH=/tmp/go GOCACHE=/tmp/go-build \
    && go install "golang.org/x/tools/gopls@${GOPLS_VERSION}" \
    && go install "github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@${OAPI_CODEGEN_VERSION}" \
    && go install "mvdan.cc/gofumpt@${GOFUMPT_VERSION}" \
    && go install "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION}" \
    && rm -rf /tmp/go /tmp/go-build

# The pod user owns /opt/nvm, so `npm install -g` and `nvm install` work. Those writes are shared by all
# sessions and vanish on restart. /opt/nvm/current is the default Node for processes that never load nvm.
ARG NVM_VERSION
ARG NODE24_VERSION
ARG NODE26_VERSION
ENV NVM_DIR=/opt/nvm
# hadolint ignore=SC1091
RUN mkdir -p "${NVM_DIR}" \
    && curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | PROFILE=/dev/null bash \
    && unset NPM_CONFIG_PREFIX \
    && . "${NVM_DIR}/nvm.sh" \
    && nvm install "${NODE24_VERSION}" \
    && nvm install "${NODE26_VERSION}" \
    && nvm alias default "${NODE26_VERSION}" \
    && ln -s "versions/node/${NODE26_VERSION}" "${NVM_DIR}/current" \
    && nvm cache clear \
    && chown -R agent:agent "${NVM_DIR}"

ENV PATH=/opt/nvm/current/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# uv tools install under $HOME by default, which is per session here, so bake pgcli at a shared path.
ARG PGCLI_VERSION
RUN UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install --no-cache \
      --python /usr/bin/python3 "pgcli==${PGCLI_VERSION}" \
    && chmod -R a+rX /opt/uv-tools

# The browser comes from the MCP server's own playwright, so its revision always matches the server's.
ARG PLAYWRIGHT_MCP_VERSION
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN npm install --prefix /opt/playwright-mcp --no-audit --no-fund "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" \
    && ln -s /opt/playwright-mcp/node_modules/.bin/playwright-mcp /usr/local/bin/playwright-mcp \
    && node /opt/playwright-mcp/node_modules/playwright/cli.js install --with-deps chromium \
    && chmod -R a+rX /opt/playwright-mcp /opt/ms-playwright \
    && rm -rf /var/lib/apt/lists/* /root/.npm

# The marketplace is renamed because Claude Code reserves claude-plugins-official for the GitHub source.
# Only the four plugins the pod enables are kept. playwright runs the pinned server above, not @latest, and
# context7 reads its API key from a Secret file through a headersHelper, not from an environment variable.
ARG CLAUDE_PLUGINS_REF
RUN mkdir -p /opt/claudetainer-plugins \
    && curl -fsSL "https://codeload.github.com/anthropics/claude-plugins-official/tar.gz/${CLAUDE_PLUGINS_REF}" \
      | tar -xz -C /opt/claudetainer-plugins --strip-components=1 \
        "claude-plugins-official-${CLAUDE_PLUGINS_REF}/.claude-plugin" \
        "claude-plugins-official-${CLAUDE_PLUGINS_REF}/plugins/gopls-lsp" \
        "claude-plugins-official-${CLAUDE_PLUGINS_REF}/plugins/feature-dev" \
        "claude-plugins-official-${CLAUDE_PLUGINS_REF}/external_plugins/context7" \
        "claude-plugins-official-${CLAUDE_PLUGINS_REF}/external_plugins/playwright" \
    && m=/opt/claudetainer-plugins/.claude-plugin/marketplace.json \
    && jq '.name = "claudetainer-plugins" | .plugins |= map(select(.name | IN("gopls-lsp", "feature-dev", "context7", "playwright")))' "$m" > /tmp/m.json \
    && mv /tmp/m.json "$m" \
    && test "$(jq '.plugins | length' "$m")" = 4 \
    && p=/opt/claudetainer-plugins/external_plugins/playwright/.mcp.json \
    && jq '.playwright.command = "playwright-mcp" | .playwright.args = []' "$p" > /tmp/p.json \
    && mv /tmp/p.json "$p" \
    && c=/opt/claudetainer-plugins/external_plugins/context7/.mcp.json \
    && jq '.mcpServers.context7 |= (del(.headers) | .headersHelper = "/usr/local/lib/claudetainer/context7-headers.sh")' "$c" > /tmp/c.json \
    && mv /tmp/c.json "$c" \
    && chmod -R a+rX /opt/claudetainer-plugins

# Root-owned, so no session can replace the binary. The updater stays off through DISABLE_AUTOUPDATER.
ARG CLAUDE_VERSION
RUN HOME=/opt/claude sh -c "mkdir -p /opt/claude && curl -fsSL https://claude.ai/install.sh | bash -s ${CLAUDE_VERSION}" \
    && ln -s /opt/claude/.local/bin/claude /usr/local/bin/claude \
    && chmod -R a+rX /opt/claude \
    && claude --version

COPY rootfs/ /
COPY --from=exporter /login-exporter /usr/local/bin/login-exporter
RUN chmod 0755 /usr/local/bin/claudetainer-start /usr/local/lib/claudetainer/*.sh \
    && mkdir -p /workspace \
    && chown agent:agent /workspace /home/agent

# Empty values override the base image's, which pointed at the removed shared files. The start script
# unsets them entirely before Claude starts.
ENV LANG=C.UTF-8 \
    BASH_ENV= \
    CLAUDE_ENV_FILE= \
    NPM_CONFIG_PREFIX= \
    DISABLE_AUTOUPDATER=1 \
    CLAUDE_CONFIG_DIR=/home/agent/.claude \
    GH_CONFIG_DIR=/home/agent/.config/gh \
    GIT_CONFIG_GLOBAL=/home/agent/.gitconfig \
    GOMODCACHE=/workspace/.cache/go-mod \
    GOCACHE=/workspace/.cache/go-build \
    npm_config_cache=/workspace/.cache/npm \
    UV_CACHE_DIR=/workspace/.cache/uv \
    PLAYWRIGHT_MCP_BROWSER=chromium \
    PLAYWRIGHT_MCP_HEADLESS=true \
    PLAYWRIGHT_MCP_NO_SANDBOX=true \
    PLAYWRIGHT_MCP_USER_DATA_DIR=/home/agent/.claude/playwright-profile

USER agent
WORKDIR /workspace
ENTRYPOINT ["tini", "--"]
CMD ["claudetainer-start"]
