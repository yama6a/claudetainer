# Runbook: Claude login

Why the login works this way: [../04_login.md](../04_login.md).

## Seal a new login

Do this for the first deploy, and again before the refresh token expires, about every 30 days.

1. Log in inside a throwaway container, so the login never touches your laptop's own. On macOS a login outside a
   container goes to the Keychain, not to a file. Run from a checkout of this repo:

   ```bash
   make login
   ```

   Open the URL, approve, and paste the code back. Expected: `Login successful`, then
   `wrote refresh-token and scopes. The refresh token expires <date>.` Note the date.

2. Seal the login with kubectl pointed at the cluster. Copy the result into the GitOps repo, then delete `login`.
   Set `LOGIN_NAMESPACE` to seal for a namespace other than `claudetainer`:

   ```bash
   make sealed-secret
   cp login/sealedsecret-claude-login.yaml <gitops-repo>/argo_apps/workloads/charts/claudetainer/templates/
   rm -rf login
   ```

   kubeseal writes the whole file, so the comment block at its top is gone. Put it back from git if you want it.

3. Commit and push the GitOps repo. Reloader restarts the pod once Argo CD syncs the SealedSecret.

4. Check the pod logged in:

   ```bash
   kubectl -n claudetainer logs deploy/claudetainer | grep 'logging in'
   kubectl -n claudetainer exec deploy/claudetainer -- claude auth status
   ```

   Expected: `new sealed refresh token, logging in`, then `"loggedIn": true` and `"authMethod": "claude.ai"`.

Never reuse a token file, and never log in again with that throwaway folder. The pod spends the token on its first
use.

## Check the login

The alert `claudetainer-login-expiring` pushes to ntfy when less than 3 days remain. To see the date now:

```bash
kubectl -n claudetainer exec deploy/claudetainer -c claudetainer -- \
  jq -r '.claudeAiOauth.refreshTokenExpiresAt / 1000 | todate' /home/agent/.claude/.credentials.json
```

Expected: a date in the future. In Grafana, `(claudetainer_login_refresh_token_expiry_timestamp_seconds - time()) / 86400`
shows the days left.

## Troubleshooting

- **The pod restarts over and over, logs `claude auth login failed`.** The sealed token was spent or revoked.
  Seal a new one.
- **Logs `no claude.ai login`.** The volume holds no working login and the sealed token was already used. Seal a
  new one.
- **After restoring the config volume from a backup,** the restored login may hold a spent refresh token. Seal a
  new one.
