# CLAUDE.md - claudetainer

The image for Claude Code sessions in the cluster. `docs/` holds the decisions. This file covers how the repo is
built.

## Layout

| Path | Holds |
|---|---|
| `Dockerfile` | the image. Every pinned version is an `ARG` at the top, with a `# renovate:` line above it |
| `rootfs/` | copied to `/` in the image: the start script, hook scripts, managed settings, the pod CLAUDE.md |
| `build/` | scripts the Dockerfile runs during the build only, such as the PHP compile |
| `cmd/login-exporter/` | the sidecar that serves the login expiry as metrics. Go, org conventions |
| `test/smoke.sh` | checks a built image: every tool, its exact version, its path |
| `renovate.json5` | which manager owns which pin |
| `.github/workflows/` | CI, release and deploy, Renovate. All call yama6a/gha |
| `Makefile` | a copy of gha's `templates/Makefile.go`, with the image targets below it |
| `docs/NN_topic.md` | decisions. `docs/runbooks/NN_topic.md` holds the procedures |
| `chart-draft/` | gitignored. The chart for offgrid-private, until it moves there |

## Commands

```bash
make ci          # after any Go change
make lint-image  # always, before a commit
make smoke       # after any Dockerfile, rootfs or Go change
```

## Rules

- Shell: `#!/usr/bin/env bash`, `set -euo pipefail`, shfmt `-i 2 -ci -bn -sr`. Knobs in a `# ---- knobs ----`
  block with one trailing comment each.
- ASCII only, in code and docs.
- Comments: zero by default. One line, only for a WHY the code cannot show: an outside constraint, a footgun, a
  coupling with another file.
- A new tool: an `ARG` with its `# renovate:` line, an install for amd64 and arm64, a probe in
  `test/smoke.sh`, and an entry in the tools table of `rootfs/etc/claude-code/CLAUDE.md`.
- Never pass a global flag before `claude remote-control` in the start script. It refuses to start.
- Never set `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` or `DISABLE_GROWTHBOOK`. Either turns Remote Control off.
- Never add a WorktreeRemove hook. `claude rc` runs it for every live session at shutdown, see
  `docs/02_sessions.md`.
- Never change `SERVER_DIR` in the start script or the pod hostname. The server finds its sessions again by both.

## Where a value lives

| Value | Lives in |
|---|---|
| Tool versions, the base image digest, the plugin marketplace commit | `Dockerfile` `ARG`s and `FROM` |
| Session rules: sweep age, cache limit | knobs in `rootfs/usr/local/lib/claudetainer/sweep.sh` |
| The default PHP version, PHP's `memory_limit` | `rootfs/etc/mise/config.toml`, `rootfs/etc/php/claudetainer/` |
| claudetainer's hooks, transcript retention | `rootfs/etc/claude-code/managed-settings.json` |
| Pod resources, volumes, identity, scratch quota | `values.yaml` of the chart in offgrid-private |
| Personal Claude config | `files/claude/` of the chart in offgrid-private |
