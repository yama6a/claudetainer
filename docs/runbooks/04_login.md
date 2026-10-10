# Runbook: Claude login

Why the login works this way: [../04_login.md](../04_login.md).

## Seal a new login

Do this for the first deploy, and again before the refresh token expires, about every 30 days.

1. Log in inside a throwaway container, so the login never touches your laptop's own. On macOS a login outside a
   container goes to the Keychain, not to a file. Run from a checkout of the GitOps repo:

   ```bash
   mkdir -m 0700 login
   docker run --rm -it -v "$PWD/login:/out" --entrypoint bash ghcr.io/yama6a/claudetainer:<release>
   ```

2. Inside the container, log in and write out the token and its scopes:

   ```bash
   export CLAUDE_CONFIG_DIR="$(mktemp -d)"
   claude auth login --claudeai        # open the URL, approve, paste the code back
   jq -r '.claudeAiOauth.refreshToken' "$CLAUDE_CONFIG_DIR/.credentials.json" > /out/refresh-token
   jq -r '.claudeAiOauth.scopes | join(" ")' "$CLAUDE_CONFIG_DIR/.credentials.json" > /out/scopes
   jq -r '.claudeAiOauth.refreshTokenExpiresAt / 1000 | todate' "$CLAUDE_CONFIG_DIR/.credentials.json"
   exit
   ```

   Expected: `Login successful`, then the expiry date. Note it. `scopes` must contain `user:sessions:claude_code`.

3. Seal both files and delete them:

   ```bash
   kubectl create secret generic claudetainer-claude-login -n claudetainer --dry-run=client -o yaml \
       --from-file=refresh-token=login/refresh-token --from-file=scopes=login/scopes \
     | kubeseal --controller-namespace sealed-secrets --controller-name sealed-secrets --format yaml \
     > argo_apps/workloads/charts/claudetainer/templates/sealedsecret-claude-login.yaml
   rm -rf login
   ```

   kubeseal writes the whole file, so the comment block at its top is gone. Put it back from git if you want it.

4. Commit and push the GitOps repo. Reloader restarts the pod once Argo CD syncs the SealedSecret.

5. Check the pod logged in:

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
