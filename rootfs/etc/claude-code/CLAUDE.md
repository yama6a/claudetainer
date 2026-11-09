# Running in claudetainer

This session runs in a Kubernetes pod. Other Claude Code sessions run in the same pod, as the same user.

## Your folder

- Your working directory is your session folder under `/workspace/sessions/`. Clone every repo into it.
- Never read or change another session's folder.
- The folder is deleted 30 days after the session's last message. Push work to GitHub early.
- `HOME` is `.home` inside your folder. `go install`, `uv tool install` and `~/.local/bin` stay yours.
- `/workspace/.cache` holds the shared caches for Go, npm, uv, Composer and mise.

## Tools

No sudo, no apt. Put a missing tool in `~/.local/bin`, or add it to the image with a pull request to
`yama6a/claudetainer`.

| Area | Tools |
|---|---|
| Base | git, gh, curl, wget, jq, yq, rg, make, file, tar, xz, zip, unzip, rsync, ssh, dig, lsof |
| Build | gcc, g++, pkg-config, autoconf, perl, python3 |
| Python | uv, uvx. No pip: use `uv run`, `uv tool install` or `uvx` |
| Go | go, gopls, golangci-lint, gofumpt, govulncheck, oapi-codegen, dlv |
| Node | nvm with Node 24 and 26, npm, npx |
| PHP | mise with PHP 8.2, 8.3, 8.4 and 8.5, Composer, Xdebug, PCOV, Intelephense |
| Kubernetes | kubectl, helm 4, kustomize, kubeconform, kubeseal, kubectx, kubens, k9s |
| Talos | talosctl, read-only |
| Lint | shellcheck, shfmt, actionlint, hadolint, yamllint, prettier, renovate, renovate-config-validator |
| Databases | psql 18, pgcli, sqlite3. A Postgres 18 server on `localhost:5432` in a sidecar container |
| Browser | headless Chromium through the Playwright MCP server |
| Plugins | gopls-lsp, php-lsp, feature-dev, context7, playwright. victoriametrics and victorialogs when the pod configures them |

- No Docker daemon. `docker build`, `docker run` and `act` fail.
- Postgres: `PGSANDBOX_DSN` points at the sidecar, so pgsandbox tests run here. Each test process gets databases
  of its own. Tests that pin another Postgres major fail. The sidecar has a 1Gi memory limit.
- Each Bash command starts in a fresh shell. Switch a runtime in the same command.
- Node: 26 is the default. `nvm use 24 && npm test`, or `nvm exec 24 npm test`.
- PHP: 8.5 is the default. `MISE_PHP_VERSION=8.3 composer test`, or `mise exec php@8.3 -- vendor/bin/phpunit`.
  A repo's `.tool-versions` or `mise.toml` selects its version. Run `mise trust` once for a `mise.toml`.
- mise compiles a missing PHP version in 10 to 20 minutes. It does this on `mise install php@<version>`, and
  when a repo asks for a version that is not installed.
- Xdebug and PCOV are not loaded. Load one per command: `php -d extension=pcov vendor/bin/phpunit --coverage-text`,
  or `XDEBUG_MODE=coverage php -d zend_extension=xdebug ...`.
- `npm install -g`, `nvm install` and `mise install` write to folders all sessions share. A pod restart removes
  what they add.
- GitHub: `gh` and git use the owner's account. Commits are signed automatically.
- CI: run tests locally, then push and read the GitHub Actions results with `gh run`.

## Memory

All sessions share one memory limit. When the pod reaches it, the pod restarts and every session loses its work.

- Before you finish, stop every background process you started: servers, watchers, `tail -f`. Stop only your
  own processes.
- PHP `memory_limit` is 1G. Raise it for one command only: `php -d memory_limit=2G ...`,
  `phpstan analyse --memory-limit=2G`, `COMPOSER_MEMORY_LIMIT=2G composer update`.
- Never raise it in an ini file or with `export`.

## Cluster

- kubectl has cluster-admin. The default namespace is `claudetainer-scratch`.
- Deploy experiments to `claudetainer-scratch` only. Its quota is small. Objects older than 7 days are deleted.
- Query VictoriaMetrics and VictoriaLogs through their MCP tools. For an endpoint the tools lack, curl
  `$VM_INSTANCE_ENTRYPOINT` or `$VL_INSTANCE_ENTRYPOINT` from this pod. Never start a pod to query them.
- Start a scratch pod only for what this pod cannot do: run a container image, or test on a node of another
  architecture or under a memory limit. For another in-cluster service, use `kubectl port-forward` from here.
- Delete every scratch pod you start before you finish, then check with `kubectl get pods`. A finished pod that
  stays behind fires the pod-not-ready alert.
- Never pipe `kubectl run --rm` into another command. If the reader exits early, kubectl dies before it deletes
  the pod.
- Change other namespaces only when the user asks. Pull requests to the cluster's GitOps repo manage the live
  cluster, and Argo CD reverts manual changes.

## Show files to the user

The user reads the session in the Claude app or on claude.ai. Sessions here are not on a project thread, so
`SendUserFile` fails with "nowhere to place a file".

- Image, such as a screenshot: save it in your session folder, then open it with the Read tool. The app shows every
  image you read as a thumbnail.
- Text or Markdown: put the content in your reply. The app renders Markdown.
- Never push a file to GitHub only to show it to the user.
