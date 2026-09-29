# Access

What a session can reach, with which credential, and the risks accepted with it. Procedures are in
[runbooks/06_access.md](runbooks/06_access.md).

## Credentials

| Credential | Secret | Grants |
|---|---|---|
| Fine-grained GitHub PAT on yama6a | `claudetainer-github` | on the repos you pick, offgrid-private included: Contents, Pull requests and Workflows read/write, Actions and Metadata read |
| SSH signing key | `claudetainer-signing-key` | signs commits as you. Registered on GitHub as a signing key only |
| Claude login | `claudetainer-claude-login` | the Max subscription, see [04_login.md](04_login.md) |
| ServiceAccount `claudetainer` | none, projected token | cluster-admin |
| talosconfig with `os:reader` | `claudetainer-talosconfig` | reads node state, services and logs. Changes nothing |
| Context7 API key | `claudetainer-context7`, optional | a higher rate limit for the context7 plugin |

Commits carry the identity `Yama <10947332+yama6a@users.noreply.github.com>`. PRs show you as the author.

## Network

Cilium runs with `policyAuditMode: true`. Every policy below only logs a would-be drop until that changes.

| Policy | Ingress | Egress |
|---|---|---|
| `claudetainer` | vmagent on port 9100 | DNS, the internet on any port, the API server, claudetainer-scratch, the nodes on port 50000 |
| `claudetainer-scratch-wipe` | none | DNS, the API server |
| `scratch` in claudetainer-scratch | from claudetainer and from pods in the namespace | DNS, the internet, pods in the namespace |

## Scratch namespace

`claudetainer-scratch` is where sessions deploy experiments. The pod CLAUDE.md tells them so, and their
kubeconfig defaults to it. Nothing enforces it: cluster-admin reaches every namespace.

| Limit | Value |
|---|---|
| memory | 2 GiB requests and limits |
| cpu | 1 core of requests |
| pods | 10 |
| volumes | 20 GiB of PVC requests |
| LoadBalancer and NodePort Services | 0 |
| container defaults | 50m and 64 MiB requested, 256 MiB limit |

The CronJob `claudetainer-scratch-wipe` deletes every object older than 7 days. It skips objects Argo CD manages,
objects with an owner, which garbage collection removes, and `kube-root-ca.crt` and the default ServiceAccount.

## Decisions

- **Your own account, a fine-grained PAT.** No second account or GitHub App to run. Cost: you cannot approve a
  session's PR yourself. Your repos require no reviews, so this changes nothing today.
- **A dedicated signing key.** Your laptop key never leaves the laptop. Revoke the pod's key on GitHub if it
  leaks.
- **cluster-admin.** Sessions can debug and fix anything. Cost: see the risks below.
- **Talos read-only.** Enough to read logs and node state. A reader certificate cannot change a node.
- **Egress to the internet on every port.** Tasks fetch from arbitrary hosts. Cost: every LAN host outside the
  cluster is reachable too, the NAS and the router included.
- **LoadBalancers blocked in scratch.** One would take a LAN IP from Cilium's pool.
- **The Context7 key through a headersHelper, not an environment variable.** Secrets stay files, so the key never
  reaches the environment of Bash commands. The Secret is optional: the pod starts without it.

## Accepted risks

A session runs in bypass mode, so a prompt injection in a cloned repo or a fetched page runs with every credential
above. It can:

- act as cluster admin, and delete volumes whose data Argo CD cannot restore.
- push to offgrid-private's main, which needs no PR and no review. Argo CD applies it to the cluster.
- push a branch whose workflow reads repo secrets such as DEPLOY_TOKEN.
- reach Argo CD's API, which grants admin to anonymous callers inside the cluster.
- read or change every other session's folder, since all sessions run as one user.
