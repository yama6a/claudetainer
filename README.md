# claudetainer

Claude Code sessions that run in the homelab cluster, driven from claude.ai/code and the Claude app.

- One pod runs Claude Code's own Remote Control server. You start, chat with and archive sessions from any device.
- Each session works in its own folder, with airlock's tools, a GitHub login that signs commits, and kubectl.
- Sessions survive pod restarts: the server brings them back when it starts again.

This repo builds the image `ghcr.io/yama6a/claudetainer`. The Kubernetes manifests live in offgrid-private. A
draft of them sits in `chart-draft/`, which git ignores because it holds a copy of personal Claude config.

## Docs

| Doc | Covers |
|---|---|
| [01_architecture.md](docs/01_architecture.md) | what runs, why there is no backend, restarts |
| [02_sessions.md](docs/02_sessions.md) | folders, hooks, HOME, caches, the sweep |
| [03_image.md](docs/03_image.md) | base image, tools, plugins, CI and release |
| [04_login.md](docs/04_login.md) | the Claude login and its renewal |
| [05_deployment.md](docs/05_deployment.md) | the chart, volumes, the pod |
| [06_access.md](docs/06_access.md) | credentials, network, scratch namespace, accepted risks |
| [07_verify.md](docs/07_verify.md) | claims to test after the first deploy |

Procedures are in [docs/runbooks/](docs/runbooks/).

## Development

```bash
make ci          # the Go checks CI runs: tidy, fmt, golangci-lint, vet, tests, govulncheck
make lint-image  # shellcheck, shfmt, hadolint, yamllint, actionlint
make smoke       # build for the local architecture and check every pinned tool
```

## Licence

MIT, see [LICENSE](LICENSE).
