# Architecture

Claudetainer runs Claude Code sessions in the cluster. You start, drive and archive them from claude.ai/code or
the Claude app. The pod holds the tools, the clones and the credentials. There is no claudetainer UI.

## What runs

| Piece | Where | Does |
|---|---|---|
| Remote Control server | one `claude remote-control` process, the container's main process | registers with claude.ai, spawns a Claude Code process per session, streams each one to your devices |
| Session | a child process of the server | works in its own folder under `/workspace/sessions/` |
| Hook scripts | `/usr/local/lib/claudetainer/` in the image | give each session a folder and a HOME, and sweep old folders |
| Pod | Deployment `claudetainer`, namespace `claudetainer`, `replicas: 1` | one server, every session |
| Chart | `argo_apps/workloads/charts/claudetainer/` in the GitOps repo | the pod, its volumes, secrets, RBAC and the scratch namespace |

Remote Control (RC) is Claude Code's own bridge to claude.ai. The server only makes outbound HTTPS calls to
`api.anthropic.com`, so the pod needs no ingress, no hostname and no SSO entry.

A session starts like this:

1. In claude.ai/code or the app you start a session and pick the server `claudetainer`.
2. The server runs the WorktreeCreate hook, which creates `/workspace/sessions/<name>/`.
3. The server starts a Claude Code process in that folder. Its SessionStart hook points HOME into the folder.
4. You chat with it from any device. It clones what it needs, works, pushes and opens PRs.

Session handling is in [02_sessions.md](02_sessions.md), the image in [03_image.md](03_image.md), the login in
[04_login.md](04_login.md), the chart in [05_deployment.md](05_deployment.md) and credentials in
[06_access.md](06_access.md). Claims still to test are in [07_verify.md](07_verify.md).

## Restarts

`claude remote-control` started again in the same folder, with the same config, brings back every session it
served. This works for about 4 hours after it stopped. So a restart pauses all sessions and resumes them, as
long as `~/.claude` and `/workspace` survive it. Both are Longhorn volumes.

| Event | Effect |
|---|---|
| A deploy, a Reloader restart, a node drain | every session pauses for the restart, then resumes. A turn that was running is lost |
| The server exits after about 10 minutes without network | Kubernetes restarts the container, sessions resume |
| The pod stays down longer than about 4 hours | its sessions stay archived. Start new ones. The old folders stay until the sweep |

## Decisions

- **Claude Code's own server, no backend.** claude.ai and the app already start, list, end and archive sessions
  and keep their history. A Go backend and a web UI would repeat that. What remains is plumbing, which the image
  and a few hook scripts cover.
- **Sessions start from claude.ai or the app.** In server mode the claudetainer pod cannot start a session
  itself. It has no need to: the picker in claude.ai lists the server.
- **One pod, one server.** Anthropic refresh tokens are single-use. A copied login breaks the other copy on its
  first refresh, so one login can live in one place only. A pod per session would need a browser login per pod.
- **Self-hosted environments are out.** They need a Team or Enterprise plan. The account is on Max, where
  Remote Control is available.
- **Deployment with `strategy: Recreate`, fixed hostname.** Two servers on one folder archive each other's
  sessions, and both volumes are ReadWriteOnce. The pod hostname names the server in the picker, so it stays
  `claudetainer` across restarts.
- **Auto-deploy every release, like codarr.** Every merged Renovate bump restarts the pod. Sessions resume, a
  running turn is lost.
- **No node preference.** The pod may run on a Pi. There only about 2 GiB of memory is free, so the 6 GiB limit
  is only real on tc-w1.
- **No web terminal, no Go supervisor.** Kubernetes restarts the server. The login comes from a sealed token,
  see [04_login.md](04_login.md).

## Known limits

- The app's diff pane stays empty. It needs the session folder to be a git repo, and session folders hold clones.
- A session switched to another permission mode in the app cannot switch back to bypass from the app.
- `/plugin` and `/resume` work only in a local terminal. The start script installs the plugins.
- The Fable usage-credits prompt is not forwarded to the app, so a turn that needs it ends unanswered.
- Never set `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` or `DISABLE_GROWTHBOOK`. Either one turns Remote Control
  off.
- `claude remote-control` refuses a global flag such as `--settings` before `remote-control`. Settings go in files.
