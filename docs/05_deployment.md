# Deployment

The chart lives in offgrid-private at `argo_apps/workloads/charts/claudetainer/`. This repo carries a draft of it
in `chart-draft/`, which git ignores. Procedures are in [runbooks/05_deployment.md](runbooks/05_deployment.md).

## Resources

| Object | Namespace | Notes |
|---|---|---|
| Deployment `claudetainer` | claudetainer | 1 replica, `Recreate`, hostname `claudetainer`, plus the `login-exporter` sidecar |
| PodMonitor `claudetainer` | claudetainer | vmagent scrapes the sidecar on port 9100 every 60 s |
| PVC `claudetainer-config` | claudetainer | `~/.claude`, 10 GiB, `longhorn-r2-retained-with-backups`, never pruned by Argo CD |
| PVC `claudetainer-workspace` | claudetainer | `/workspace`, 100 GiB, `longhorn-r2-ephemeral` |
| ConfigMap `claudetainer-user-config` | claudetainer | your personal Claude config |
| 5 SealedSecrets | claudetainer | GitHub PAT, Claude login, signing key, talosconfig, Context7 key (optional) |
| ServiceAccount and ClusterRoleBinding | claudetainer | cluster-admin |
| Namespace, ResourceQuota, LimitRange | claudetainer-scratch | see [06_access.md](06_access.md) |
| CronJob `claudetainer-scratch-wipe` | claudetainer | daily at 03:00 UTC |
| Grafana alert file `claudetainer.yaml` | `argo_apps/platform/charts/05_grafana/files/alerts/` | the login expiry rule, see [04_login.md](04_login.md) |
| 3 CiliumNetworkPolicies | both | see [06_access.md](06_access.md) |

## Pod

| Setting | Value | Why |
|---|---|---|
| memory | 1.5 GiB request, 6 GiB limit | one idle session uses about 0.5 GiB, a build GBs more |
| cpu | 500m request, no limit | actual node CPU use is 16 to 24 percent |
| `/dev/shm` | 1 GiB memory volume | Chromium dies on real pages with the 64 MiB default |
| `terminationGracePeriodSeconds` | 120 | the server gives sessions 30 s to stop, then cleans up |
| user | uid and gid 1000, `fsGroup` 1000, `OnRootMismatch` | a fresh Longhorn volume mounts as root. Without `OnRootMismatch`, every start chowns 100 GiB |
| probes | none | the container exits when the server exits |
| sidecar | `login-exporter`, 16 MiB request, 32 MiB limit, read-only root filesystem | reads the config volume read-only |
| labels | `app`, `longhorn-replica-affinity/enabled` | the webhook prefers nodes that hold the volumes' replicas |

## Personal config

The ConfigMap holds your CLAUDE.md, rules, the Terse output style, the skills context7-mcp and go-deslop, a pod
variant of git-commit, the dry-up-code command, the hooks git-guard.sh and no-slop-chars.sh, and settings.json.
The start script copies them into `~/.claude` at every start and deletes files dropped from the ConfigMap.

The pod's settings.json is your laptop's minus the Nordnet marketplace, plugins and paths, minus the `ask`
rules, plus `inputNeededNotifEnabled: true`. Its plugin names point at `claudetainer-plugins`.

## Decisions

- **The chart in offgrid-private, not here.** App repos ship no manifests. Argo CD reconciles offgrid-private.
- **Two volumes.** The config is small and has no other copy, so it gets the backed-up class and deletion
  protection. The workspace is rebuilt by cloning again, so it gets the general-purpose class. `-local` is
  reserved for small volumes by offgrid-private's storage doc: it copies the whole volume on every reschedule.
- **10 GiB config.** The laptop writes about 0.5 GiB of transcripts a month. 365-day retention needs about 6 GiB.
- **The ConfigMap over a copy in the image.** Your config changes more often than the tools. Cost: every change
  restarts all sessions.
- **claudetainer's own hooks and pod CLAUDE.md in the image.** They name scripts in the image, so they ship with
  them. Your settings cannot override managed settings.
- **No `alert-criticality` label.** Every alert already goes to ntfy, and warning is the default.
