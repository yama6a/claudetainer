# Open items

Claims the design rests on that only a running pod can confirm. Test them after the first deploy, in this order.
Each one names what changes when it fails.

| # | Claim | Status |
|---|---|---|
| 1 | `claude auth login` with the sealed refresh token gives a login Remote Control accepts | TODO |
| 2 | Sessions come back after a pod restart | TODO |
| 3 | Sessions come back after the server exits on a 10-minute network outage | TODO |
| 4 | The server stops within the 120 s grace period and keeps every session folder | TODO |
| 5 | The WorktreeCreate hook gets the same `bridge-*` name on resume, and the transcript folder matches the session folder | TODO |
| 6 | A login that expires while the server runs makes the container exit | TODO |
| 7 | bypassPermissions starts without a prompt in server-spawned sessions | TODO |
| 8 | The picker shows the server as `claudetainer` | TODO |
| 9 | The SessionStart hook receives a per-session `CLAUDE_ENV_FILE` in server-spawned sessions | TODO |
| 10 | The Playwright MCP server starts Chromium in the pod | TODO |
| 11 | The five plugins install from `/opt/claudetainer-plugins` at start | TODO |
| 12 | With Trusted Devices turned on, the pod's login still works | TODO, only if you turn it on |
| 13 | Claude Code runs the plugin's headersHelper, and context7 calls carry the key | TODO |
| 14 | vmagent scrapes the login exporter, and Grafana loads the rule `claudetainer-login-expiring` | TODO |

Already confirmed in a local container: headless Chromium starts without a sandbox, commits are signed, nvm
switches between 24 and 26, `npm install -g` works, the hooks create and sweep folders, and the start script syncs
a ConfigMap layout.

## 1. Login from the sealed token

```bash
kubectl -n claudetainer logs deploy/claudetainer | grep -i 'logging in\|login'
kubectl -n claudetainer exec deploy/claudetainer -- claude auth status
```

Expected: `"loggedIn": true`, `"authMethod": "claude.ai"`, and the server listed in claude.ai/code.
If it fails: the scopes are wrong or the token was spent. Seal a new one, see
[runbooks/04_login.md](runbooks/04_login.md).

## 2. Resume after a restart

1. Start a session from the app and send it a prompt that takes a minute.
2. `kubectl -n claudetainer rollout restart deploy/claudetainer`.
3. Send the session a message once the pod is Running.

Expected: the session answers, and `ls /workspace/sessions` still lists its folder.
If it fails: restarts end sessions. Check whether the hostname or the server folder changed.

## 3. Resume after a network outage

Block egress for 12 minutes, for example with a temporary CiliumNetworkPolicy after audit mode is off, or by
cutting the node's uplink. Expected: the container restarts once and sessions answer again.

## 4. Shutdown

```bash
kubectl -n claudetainer delete pod -l app=claudetainer --wait=false
kubectl -n claudetainer logs -f -l app=claudetainer --tail=20
```

Expected: `SIGTERM received` then a clean exit well inside 120 s, and every folder still in place afterwards.
If it fails: raise `app.terminationGracePeriodSeconds`.

## 5. Folder and transcript names

```bash
kubectl -n claudetainer exec deploy/claudetainer -- ls /workspace/sessions /home/agent/.claude/projects
```

Expected: each `bridge-<id>` folder has a transcript folder `-workspace-sessions-bridge-<id>`.
If it fails: the sweep falls back to folder timestamps and may delete active sessions. Fix `sweep.sh`.

## 6. Mid-run login expiry

Revoke the pod's login from claude.ai settings, then watch the pod for 10 minutes.
Expected: the container exits and `container-high-restarts` fires. If it stays up, nothing alerts on an expired
login. Add a log-based alert or a calendar reminder for the 30-day renewal.

## 7 to 11. Session behaviour

Start a session from the app and ask it to run, one per line:

```bash
echo "$HOME $KUBECONFIG"
kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}'
claude plugin list
```

Expected: HOME under the session folder, namespace `claudetainer-scratch`, five plugins enabled, and no
permission prompt at any point. Then ask it to open a page with the Playwright tools.

## 13. Context7 key

In a session, run `/mcp` from the app. Expected: context7 connected. If Context7 still reports the anonymous rate
limit, the helper did not run: check the pod's debug output for `headersHelper`.

## 14. Login expiry alert

In Grafana, query `claudetainer_login_refresh_token_expiry_timestamp_seconds`. Expected: one series with the date
from the login check in [runbooks/04_login.md](runbooks/04_login.md). Then open Alerting and find
`claudetainer-login-expiring` in the `claudetainer` group, state Normal.
