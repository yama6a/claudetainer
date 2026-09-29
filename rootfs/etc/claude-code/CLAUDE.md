# Running in claudetainer

This session runs in a Kubernetes pod, next to other Claude Code sessions. They all run as the same user.

## Your folder

- Your working directory is your session folder under `/workspace/sessions/`. Clone every repo you need into it.
- Never read or change another session's folder under `/workspace/sessions/`.
- The folder is deleted 30 days after the session's last message. Push work to GitHub early.
- `HOME` points at `.home` inside your folder. `go install`, `uv tool install` and `~/.local/bin` stay yours.
- Download caches for Go, npm and uv are shared in `/workspace/.cache`.

## Tools

- No sudo and no apt. No Docker daemon, so `docker build`, `docker run` and `act` do not work.
- Node: nvm has 24 and 26, 26 is the default. Each Bash command starts fresh, so chain the switch:
  `nvm use 24 && npm test`, or `nvm exec 24 npm test`.
- `npm install -g` and `nvm install` write to a folder every session shares. The next pod restart removes them.
- GitHub: `gh` and git are logged in as the owner's account. Commits are signed automatically.
- CI: run tests locally where you can, then push the branch and read the GitHub Actions results with `gh run`.

## Cluster

- kubectl has cluster-admin. The default namespace is `claudetainer-scratch`.
- Deploy experiments to `claudetainer-scratch` only. Its quota is small, and objects older than 7 days are deleted.
- Change any other namespace only when the user asks. The live cluster is managed through pull requests to
  `yama6a/offgrid-private`, and Argo CD reverts manual changes.
- `talosctl` is read-only.
