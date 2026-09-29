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

The sweep runs at most once an hour. To run it at once, delete its stamp first:

```bash
kubectl -n claudetainer exec deploy/claudetainer -- sh -c 'rm -f /workspace/.sweep.stamp && /usr/local/lib/claudetainer/sweep.sh'
```

To delete one folder by hand, archive its session in claude.ai first, then:

```bash
kubectl -n claudetainer exec deploy/claudetainer -- sh -c 'chmod -R u+w /workspace/sessions/<name> && rm -rf /workspace/sessions/<name>'
```

## Restart the server

```bash
kubectl -n claudetainer rollout restart deploy/claudetainer
```

Expected: sessions pause and answer again within a few minutes. A turn that was running is lost.

## A session is gone after a long outage

The server brings sessions back for about 4 hours after it stopped. After that, start a new session. Its folder
and transcript stay on disk until the sweep. Point the new session at the old folder to continue the work.
