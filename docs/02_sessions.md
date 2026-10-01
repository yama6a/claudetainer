# Sessions

Each session gets a folder, a HOME inside it, and shared download caches. A sweep frees the disk. Procedures are
in [runbooks/02_sessions.md](runbooks/02_sessions.md).

## Layout

| Path | Holds | Removed by |
|---|---|---|
| `/workspace/sessions/home/` | the server's own folder, and the session it pre-creates at start | never, it is fixed |
| `/workspace/sessions/home/*` | whatever that session cloned | the sweep, 30 days after the newest file changed |
| `/workspace/sessions/bridge-<id>/` | one on-demand session: its clones | the sweep, 30 days after its last transcript write |
| `/workspace/sessions/scheduled-<name>-<time>/` | one scheduled session: its clones | the sweep, 30 days after its last transcript write |
| `<session folder>/.home/` | that session's HOME: GOPATH, `~/.local`, its kubeconfig | with its folder |
| `/workspace/.cache/` | Go module and build caches, npm and uv caches, shared | the sweep, whole, above 20 GiB |
| `/opt/nvm/` | Node 24 and 26, and whatever `npm install -g` adds | the next pod restart |
| `~/.claude/projects/` | transcripts, one folder per session folder | Claude Code, after 365 days |

The volume is 100 GiB, see [05_deployment.md](05_deployment.md).

## Hooks

claudetainer's hooks live in `/etc/claude-code/managed-settings.json` in the image. Claude Code merges them with
the hooks in your personal settings.

| Hook | Script | Does |
|---|---|---|
| WorktreeCreate | `worktree-create.sh` | a `bridge-*` name gets `/workspace/sessions/<name>/`, the same folder again on resume. Any other name, such as a subagent's, gets a real `git worktree` |
| SessionStart | `session-start.sh` | writes HOME, GOPATH, KUBECONFIG and PATH into the session's env file, which Claude Code sources before every Bash command |

The env file reaches Bash commands only. Hooks, gopls and MCP servers keep `HOME=/home/agent`. So the cache
locations are set in the container environment, not per session.

## Scheduled sessions

A scheduled session is a session that starts on a cron schedule with a fixed prompt. You read and answer it in
claude.ai like any other session.

1. A CronJob in the chart runs `kubectl exec` into the claudetainer pod. It passes a name and pipes the prompt.
2. `scheduled-session.sh` creates `/workspace/sessions/scheduled-<name>-<time>/`.
3. It starts `claude --bg --remote-control` there. The session shows in claude.ai as `<name> <time>`.

Background sessions run under Claude Code's own supervisor process inside the pod, apart from the
`claude remote-control` server.

## Decisions

- **`claude --bg --remote-control`, not a session from the server.** The server cannot start a session itself.
  A background session with Remote Control shows in claude.ai and uses the pod's login.
- **Started by `kubectl exec`, not by a pod of its own.** A second pod needs its own login, because a refresh
  token works once. Cost: a ServiceAccount that may exec into the claudetainer pod, see
  [06_access.md](06_access.md).
- **Schedule and prompt in the chart, the start script in the image.** The prompt is personal. The way to start
  a session is the same for every user.
- **A pod restart stops a running scheduled session.** The supervisor dies with the pod. The server brings back
  only its own sessions. The next run starts a new session.

- **A folder per session, from `--spawn worktree` and a WorktreeCreate hook.** Git worktrees of one repo do not
  fit sessions that clone several repos. The hook-created folder is empty, and Claude clones into it.
- **No WorktreeRemove hook.** In Claude Code 2.1.283, `claude rc` runs that hook for every live session at
  shutdown, not only on archive. A folder counts as clean unless it is itself a git repo, and ours hold clones one
  level down. So a WorktreeRemove hook would delete uncommitted work on every restart. The sweep cleans up
  instead.
- **Staleness is the last transcript write.** A folder's own timestamp does not change when files deeper inside
  do. Claude Code names the transcript folder after the working directory, every non-alphanumeric character
  turned into `-`, so the sweep finds it from the path. The home session is long-lived, so its subfolders go by
  their newest file instead.
- **30 days.** Matches Claude Code's default transcript retention. The workspace volume is sized for it.
- **The sweep runs detached, at most once an hour.** The WorktreeCreate hook must print its path and return, so
  it starts the sweep in the background under a lock.
- **No sudo, HOME per session.** Tools that install into HOME stay inside one session and vanish with its folder.
  Anything that needs root must go into the image.
- **Shared download caches.** Go, npm and uv caches are content-addressed and safe for parallel use. Cost: a
  session can poison an entry the others then read. The sweep wipes the cache whole above 20 GiB.
- **nvm writable and shared.** nvm refuses to switch Node while an npm prefix outside its folder is set, so there
  is no per-session npm prefix. `npm install -g` and `nvm install` write into `/opt/nvm`, shared by every session
  and lost on restart.
- **Per-session kubeconfig.** `kubens` in one session changes only that session. Git and gh config stay shared,
  sessions only read them.
- **bypassPermissions.** Sessions never stop for approval. The credential scopes in
  [06_access.md](06_access.md) are the only fence.
- **Transcripts kept 365 days.** claude.ai keeps its own copy. The local one is on the backed-up config volume.
- **Nothing else shared.** No read-only reference folders. The personal config reaches every session anyway.

All sessions run as the same user, so a session can read or change another's folder. Only separate pods would
stop that, see [01_architecture.md](01_architecture.md).
