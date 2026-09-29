# Claude login

The server needs a full claude.ai login. It gets one from a sealed refresh token, used once. Procedures are in
[runbooks/04_login.md](runbooks/04_login.md).

## Which login works

| Credential | Remote Control |
|---|---|
| `/login` or `claude auth login` with a claude.ai account | yes |
| `claude setup-token` or `CLAUDE_CODE_OAUTH_TOKEN` | no: "can only make model requests" |
| `ANTHROPIC_API_KEY` | no |

A login stores an access token and a refresh token in `~/.claude/.credentials.json`. Claude Code swaps the
refresh token for new tokens when the access token expires. Each refresh token works once. On the laptop the
refresh token's own expiry sat 30 days after the login that created it, so plan on a new login every 30 days.
Claude Code warns 3 days before a login expires.

## How the pod logs in

1. On your laptop you log in once with a throwaway config folder.
2. You seal that login's refresh token and scopes into the Secret `claudetainer-claude-login` and delete the
   folder.
3. At start, the pod compares the sealed token's hash with the last one it used. A new token means
   `claude auth login` with `CLAUDE_CODE_OAUTH_REFRESH_TOKEN`, which writes a fresh login to the config volume.
4. From then on, Claude Code refreshes that login on the volume by itself.

Renewal is steps 1 and 2 again. Reloader restarts the pod when the Secret changes.

## Decisions

- **A sealed refresh token over `kubectl exec` and a browser login.** It keeps the login in git like every other
  secret and needs no shell in the pod. Cost: each renewal is a new commit.
- **A throwaway login, never the laptop's.** The laptop keeps refreshing its own token. A copy of it dies the
  first time either side refreshes.
- **Log in only on a new hash.** The sealed token is spent after its first use. Using it again at every start
  would fail.
- **The start script exits when login fails.** The container then restarts, and the existing Grafana alert
  `container-high-restarts` fires after 5 restarts in an hour. It pushes to ntfy.
- **An expiry alert 3 days ahead.** A sidecar, `login-exporter`, serves `refreshTokenExpiresAt` from the
  credentials file as the metric `claudetainer_login_refresh_token_expiry_timestamp_seconds`. vmagent scrapes it,
  and the Grafana rule `claudetainer-login-expiring` pushes to ntfy when less than 3 days remain. A missing login
  reports 0, so it fires at once. The exporter is a small Go binary in this repo, in its own container so a crash
  never touches the server.
- **Secrets as files.** The refresh token goes only to the `claude auth login` command, never into the pod's
  environment.

## What this does not cover

- A login revoked early, for example from claude.ai settings, keeps its expiry date, so the expiry alert stays
  quiet. Whether the server then exits is item 6 in [07_verify.md](07_verify.md).
- The config volume's S3 backups contain the live login. A restored backup may hold a refresh token that was
  already spent. Seal a new one after a restore.
