# Image

`ghcr.io/yama6a/claudetainer` is Docker's Claude Code sandbox image plus a pinned tool layer. It builds for amd64
and arm64. Procedures are in [runbooks/03_image.md](runbooks/03_image.md).

## Base

`docker/sandbox-templates:claude-code-minimal-<version>`, pinned by digest. Docker Inc. publishes it for its
Docker Sandboxes product. It brings Ubuntu 26.04, the user `agent` (uid 1000), tini, git, gh, jq, ripgrep, make,
uv and the docker CLI.

The template is built for one agent per container. Every session here shares one pod, so the Dockerfile removes:

| Removed | Why |
|---|---|
| sudo and the `NOPASSWD` sudoers entry | one session could change the OS under all others |
| `/etc/sandbox-persistent.sh`, `BASH_ENV`, the global `CLAUDE_ENV_FILE` | an env file every session writes and every shell sources |
| `/usr/local/share/npm-global` and `NPM_CONFIG_PREFIX` | a prefix outside nvm, which nvm refuses to work with |
| the base's Claude Code under `/home/agent/.local` | unpinned and writable by the pod user |

## Tools

Every version is an `ARG` at the top of the `Dockerfile`, with a `# renovate:` line naming its source.

| Group | Tools |
|---|---|
| Claude | Claude Code, root-owned in `/opt/claude`, updater off |
| Kubernetes | kubectl, helm 4, kustomize, kubeconform, yq, kubectx, kubens, k9s |
| Talos | talosctl |
| Go | Go, gopls, golangci-lint, gofumpt, govulncheck, oapi-codegen, delve |
| Node | nvm with Node 24 and 26, 26 the default |
| PHP | mise with PHP 8.2 to 8.5, 8.5 the default. Composer, Xdebug and PCOV, Intelephense |
| Build | build-essential, pkg-config, python3, perl |
| Lint | shellcheck, shfmt, actionlint, hadolint, yamllint, prettier, Renovate |
| Databases | psql 18 from PGDG, pgcli, sqlite3 |
| Base extras | file, wget, zip, a `uvx` wrapper around `uv tool run` |
| MCP servers | mcp-victoriametrics, mcp-victorialogs |
| Browser | Playwright Chromium and the Playwright MCP server |
| Metrics | `login-exporter`, built from `cmd/login-exporter/` in a Go stage of the same Dockerfile |

## Plugins

The five official plugins, gopls-lsp, php-lsp, feature-dev, context7 and playwright, come from a copy of Anthropic's
marketplace vendored at a pinned commit in `/opt/claudetainer-plugins`. The start script installs them from
there.

- The copy is renamed `claudetainer-plugins`. Claude Code reserves `claude-plugins-official` for the GitHub
  source and refuses it from a folder.
- The playwright plugin runs `npx @playwright/mcp@latest` upstream. The copy runs the pinned server in the image
  instead. context7 talks to a hosted HTTP server, which nothing can pin.
- The context7 plugin sends `${CONTEXT7_API_KEY}` from the environment upstream. The copy uses a headersHelper,
  `context7-headers.sh`, which reads the key from the Secret file. Without the file, context7 runs anonymously.
- The browser comes from the MCP server's own Playwright, so its revision always matches the server.
- Two plugins of our own, victoriametrics and victorialogs, live in `build/plugins/`. They run the pinned MCP
  servers and read the server URLs from the pod environment. The start script installs each one only when the pod
  sets its URL: `VM_INSTANCE_ENTRYPOINT`, or `VL_INSTANCE_ENTRYPOINT`. `VM_INSTANCE_TYPE` defaults to `single`.

## Decisions

- **Docker's image over a community one or our own from scratch.** Anthropic publishes no ready-made image. The
  community Remote Control images have 0 to 6 GitHub stars each, and the image holds the Claude login, the GitHub
  token and a cluster-admin token. Docker Inc. is a publisher already trusted for the docker CLI.
- **The minimal variant, versioned tag.** The full variant ships Ubuntu's older Go and Node, which the pinned
  ones would shadow. A versioned tag such as `claude-code-minimal-0.7.0` makes every base change a numbered
  Renovate PR.
- **Not airlock's image.** airlock is built for `docker run` on a Mac: it is arm64 only, starts as root and
  seeds config from bind mounts.
- **nvm with 24 and 26.** Your repos pin Node 24 in `.nvmrc`, and CI runs that. 26 is the default for everything
  else.
- **PHP compiled from source with mise.** Prebuilt static PHP has no pdo_pgsql, no pdo_sqlite and cannot load
  Xdebug or PCOV. The Ondrej apt repository has no Ubuntu 26.04 builds, and sessions have no apt anyway. mise
  with the vfox-php plugin compiles any version, also inside a session, because the image keeps the headers.
  Cost: each version compiles for about 10 to 20 minutes per architecture. One build stage per version lets
  BuildKit compile all four at the same time.
- **PHP `memory_limit` at 1G.** One PHP process can no longer fill the pod's memory on its own. Sessions raise it
  per command only. `COMPOSER_MEMORY_LIMIT` is 1G too, because Composer raises its own limit to 1.5G otherwise.
- **Xdebug and PCOV built, not loaded.** Loaded, each slows every PHP command and adds memory. A session loads
  one with `php -d` for a coverage run.
- **One pinned Composer for all PHP versions.** vfox-php installs the newest Composer into each version, which
  nothing pins. The build removes those copies.
- **Lint tools in the image.** Sessions installed shellcheck, shfmt, actionlint, hadolint and yamllint by hand,
  again and again. These run the same checks as the org's shell and yaml CI jobs before a push.
- **Renovate on Node 24.** Renovate refuses any other Node. Its wrappers in `/usr/local/bin` call Node 24
  directly, so the session's default Node does not matter.
- **build-essential.** Without a C compiler, `go test -race` fails, and the org's go-ci and Makefile template
  run tests with `-race`.
- **No act.** The pod has no Docker daemon. The pod variant of the git-commit skill reads GitHub Actions results
  instead.
- **Plugins pinned, updated by Renovate.** Nothing updates on its own while the pod runs.
- **The exporter in Go, not a script.** It follows the org's Go conventions and CI, and needs no interpreter at
  runtime.

## CI and release

| Workflow | When | Does |
|---|---|---|
| `ci.yaml` | PRs and main | gha go-ci for the exporter, gha shell and yaml checks, the Renovate config check, and on PRs a native build of each architecture followed by `test/smoke.sh` |
| `build-push.yaml` | main | `docker-build-release-multiarch.yaml@v2`, then `deploy-gitops.yaml@v2` into the GitOps repo |
| `renovate.yaml` | nightly | gha's Renovate caller |

The build runs natively per architecture, because the apt and Playwright installs are slow and fragile under
QEMU. The smoke test asserts that every tool answers with the exact pinned version, from the expected path.
Required checks: `go / go`, `shell`, `yaml`, `renovate-config`, `build-amd64`, `build-arm64`.
