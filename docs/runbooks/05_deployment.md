# Runbook: Deployment

Why the chart looks the way it does: [../05_deployment.md](../05_deployment.md).

## First deploy

1. Create the GitHub repo `yama6a/claudetainer`, public, and push this repo to it.

2. In gha, add claudetainer rows and run both scripts:
   - `scripts/repo-settings.sh`: `claudetainer | main | false | public | go / go,shell,yaml,renovate-config,build-amd64,build-arm64`
   - `scripts/rollout-renovate-caller.sh`: `claudetainer | main |`

3. Set the repo secrets `DEPLOY_TOKEN` and `RENOVATE_TOKEN`, the same tokens the other app repos use.

4. Wait for the first release on main:

   ```bash
   gh release list --repo yama6a/claudetainer --limit 1
   ```

   Expected: release `1`. Its deploy job fails, because the GitOps repo has no claudetainer chart yet. That
   happens once.

5. Copy the draft into the GitOps repo:

   ```bash
   rsync -a chart-draft/argo_apps/ <gitops-repo>/argo_apps/
   ```

   This also adds the alert file `argo_apps/platform/charts/05_grafana/files/alerts/claudetainer.yaml`.

6. In the GitOps repo, set the first pin in `argo_apps/workloads/charts/claudetainer/values.yaml` to the release
   from step 4, for example `"ghcr.io/yama6a/claudetainer:1"`. From then on, each release's deploy job rewrites it.

7. Seal the secrets: the Claude login from [04_login.md](04_login.md), and the PAT, the signing key, the
   talosconfig and the optional Context7 key from [06_access.md](06_access.md).

8. Commit and push the GitOps repo. Argo CD creates the Application from `argo_apps/workloads/apps/templates/`.

9. Check the pod:

   ```bash
   kubectl -n claudetainer get pods,pvc
   kubectl -n claudetainer logs deploy/claudetainer --tail=30
   ```

   Expected: the pod `Running`, both PVCs `Bound`, and no `claudetainer-start:` error line. The server then shows
   as `claudetainer` in the claude.ai/code environment picker.

10. Work through [../07_verify.md](../07_verify.md).

## Change the personal config

Edit the files under `argo_apps/workloads/charts/claudetainer/files/claude/` in the GitOps repo, commit, push.
Reloader restarts the pod. Keep `settings.json` pointing its plugins at `claudetainer-plugins`, and run
`shfmt -w -i 2 -ci -bn -sr` on hook scripts, or the GitOps repo's `shell` check fails.

## Roll back an image

Revert the deploy PR in the GitOps repo that pinned the bad release. Argo CD syncs the previous pin.

## Resize a volume

Change `storage.workspace.size` or `storage.config.size` in `values.yaml` to a larger value, commit, push. Longhorn
grows the volume online. It cannot shrink one.
