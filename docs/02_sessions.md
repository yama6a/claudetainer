# Sessions

Each session gets a folder, a HOME inside it, and shared download caches. A sweep frees the disk. Procedures are
in [runbooks/02_sessions.md](runbooks/02_sessions.md).

## Layout

| Path | Holds | Removed by |
|---|---|---|
| `/workspace/sessions/home/` | the server's own folder, and the session it pre-creates at start | never, it is fixed |
| `/workspace/sessions/home/*` | whatever that session cloned | the sweep, 30 days after the newest file changed |
| `/workspace/sessions/bridge-<id>/` | one on-demand session: its clones | the sweep, once claude.ai reports the session archived or deleted |
| `/workspace/sessions/scheduled-<name>-<time>/` | one scheduled session: its clones | the sweep, once claude.ai reports the session archived or deleted |
| any other folder in `/workspace/sessions/` | belongs to no session | the sweep, 30 days after the newest file changed |
| `<session folder>/.home/` | that session's HOME: GOPATH, `~/.local`, its kubeconfig | with its folder |
| `/workspace/.cache/` | Go module and build caches, npm, uv, Composer and mise caches, shared | the sweep, whole, above 20 GiB |
| `/opt/nvm/` | Node 24 and 26, and whatever `npm install -g` adds | the next pod restart |
| `/opt/mise/` | PHP 8.2 to 8.5, and whatever `mise install` adds | the next pod restart |
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

1. A CronJob in the chart runs `kubectl exec` into the claudetainer pod.
2. When the entry has a gate script, the CronJob runs it in the pod first. Empty output ends the run with no
   session. Other output is appended to the prompt.
3. The CronJob passes a name and pipes the prompt to `scheduled-session.sh`, which creates
   `/workspace/sessions/scheduled-<name>-<time>/`.
4. It starts `claude --bg --remote-control` there. The session shows in claude.ai as `<name> <time>`.

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
- **A gate script decides if a scheduled session starts.** A check that rarely finds work can run every hour.
  The gate costs a few queries, and Claude runs only when there is work. The gate runs in the pod, so it has
  the pod's gh login and network access.
- **A pod restart stops a running scheduled session.** The supervisor dies with the pod. The server brings back
  only its own sessions. The next run starts a new session.

- **A folder per session, from `--spawn worktree` and a WorktreeCreate hook.** Git worktrees of one repo do not
  fit sessions that clone several repos. The hook-created folder is empty, and Claude clones into it.
- **No WorktreeRemove hook.** In Claude Code 2.1.283, `claude rc` runs that hook for every live session at
  shutdown, not only on archive. A folder counts as clean unless it is itself a git repo, and ours hold clones one
  level down. So a WorktreeRemove hook would delete uncommitted work on every restart. The sweep cleans up
  instead.
- **A session folder goes when claude.ai reports its session archived or deleted.** An active session keeps its
  folder at any age. A `bridge-<id>` folder carries the session ID in its name. A scheduled session's ID is in
  Claude Code's job record, `~/.claude/jobs/*/state.json`. A folder with no ID goes 30 days after its newest
  file changed, and so do the home session's subfolders.
- **An undocumented endpoint.** `GET /v1/code/sessions/<id>` on api.anthropic.com is what Claude Code itself
  reads. A Claude Code release can change it. Any answer but `archived`, `active` or a 404 keeps the folder.
- **The sweep borrows the running server's access token.** It never refreshes the token, because a refresh token
  works once. An expired token skips the session check for that day.
- **A 404 counts only when another session answered.** A token from another account gets a 404 for every
  session. That would otherwise delete every folder.
- **A daily CronJob, not a hook.** A CronJob in the chart runs the sweep through `kubectl exec` at 04:30 UTC,
  before the 05:00 Longhorn trim returns the freed blocks.
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
