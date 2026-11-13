# Runbook: Sessions

How sessions, folders and the sweep work: [../02_sessions.md](../02_sessions.md).

## See what is on disk

```bash
kubectl -n claudetainer exec deploy/claudetainer -- sh -c 'du -sh /workspace/sessions/* /workspace/.cache; df -h /workspace'
```

Expected: one line per session folder, the cache size, and the volume's free space.

## Find a session's folder

claude.ai does not show the folder name, so list folders by their last change:

```bash
kubectl -n claudetainer exec deploy/claudetainer -- ls -lt /workspace/sessions
kubectl -n claudetainer exec deploy/claudetainer -- ls -lt /home/agent/.claude/projects
```

The transcript folder `-workspace-sessions-bridge-<id>` belongs to `/workspace/sessions/bridge-<id>`.

## Free disk now

Run the daily sweep at once:

```bash
kubectl -n claudetainer create job --from=cronjob/claudetainer-sweep sweep-manual
kubectl -n claudetainer logs -f job/sweep-manual
```

Expected: one `sweep: <folder>: archived, removed` line per folder it deleted.

To delete one folder by hand, archive its session in claude.ai first, then:

```bash
kubectl -n claudetainer exec deploy/claudetainer -- sh -c 'chmod -R u+w /workspace/sessions/<name> && rm -rf /workspace/sessions/<name>'
```

## Start a scheduled session now

```bash
kubectl -n claudetainer create job --from=cronjob/claudetainer-scheduled-<name> <name>-manual
kubectl -n claudetainer logs -f job/<name>-manual
```

Expected: `backgrounded`, a short session ID and `bg-sessions: <id>: pinned`. A session `<name> <time>` shows in
claude.ai within a minute.
For an entry with a gate, `gate: no session needed` is also a normal result. The gate found no work.

## Restart the server

```bash
kubectl -n claudetainer rollout restart deploy/claudetainer
```

Expected: the new pod logs `wake: <session ID>: woken` for each session that was busy at the stop. Those
sessions continue within a minute. The others answer when you open them.

## A session is gone after a long outage

The server brings sessions back as long as claude.ai keeps its environment. When the server logs a new
environment URL after the outage, the old sessions stay offline. Start a new session then. Its folder and transcript
stay on disk until the sweep. Point the new session at the old folder to continue the work.

## Resume a scheduled session by hand

Use this when a scheduled session stays disconnected after a pod restart. Find its short ID and folder:

```bash
kubectl -n claudetainer exec deploy/claudetainer -- sh -c 'jq -r "[.daemonShort, .state, .cwd] | @tsv" /home/agent/.claude/jobs/*/state.json'
```

Respawn it in its folder. `claude --bg --resume` would start a copy with no claude.ai connection:

```bash
kubectl -n claudetainer exec deploy/claudetainer -- sh -c 'unset BASH_ENV CLAUDE_ENV_FILE NPM_CONFIG_PREFIX; cd <cwd> && claude respawn <short ID> < /dev/null'
```

Expected: `respawned <short ID>`. The session answers in claude.ai within a minute. It keeps its pin.
