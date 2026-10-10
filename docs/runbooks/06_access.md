# Runbook: Access

Why each credential has the scope it has: [../06_access.md](../06_access.md). Run every step from a checkout of
the GitOps repo. Each step leaves a SealedSecret to commit.

## GitHub PAT

1. Create a fine-grained token at GitHub, Settings, Developer settings, Fine-grained tokens:
   - Resource owner: `yama6a`.
   - Repository access: the repos sessions may work on, the GitOps repo included.
   - Permissions: Contents, Pull requests and Workflows read and write. Actions and Metadata read.
2. Save it to a file and seal it:

   ```bash
   (umask 077 && cat > pat)        # paste the token, press Enter, then Ctrl-D
   kubectl create secret generic claudetainer-github -n claudetainer --dry-run=client -o yaml \
       --from-file=token=pat \
     | kubeseal --controller-namespace sealed-secrets --controller-name sealed-secrets --format yaml \
     > argo_apps/workloads/charts/claudetainer/templates/sealedsecret-github.yaml
   rm pat
   ```

3. After the pod restarts, check it:

   ```bash
   kubectl -n claudetainer exec deploy/claudetainer -- gh auth status
   ```

   Expected: `Logged in to github.com account yama6a`.

## Signing key

1. Create the key and register it on GitHub as a signing key only:

   ```bash
   ssh-keygen -t ed25519 -N '' -C claudetainer-signing -f claudetainer_signing
   gh ssh-key add claudetainer_signing.pub --type signing --title claudetainer
   ```

2. Seal the private key and delete both files:

   ```bash
   kubectl create secret generic claudetainer-signing-key -n claudetainer --dry-run=client -o yaml \
       --from-file=id_ed25519=claudetainer_signing \
     | kubeseal --controller-namespace sealed-secrets --controller-name sealed-secrets --format yaml \
     > argo_apps/workloads/charts/claudetainer/templates/sealedsecret-signing-key.yaml
   rm claudetainer_signing claudetainer_signing.pub
   ```

3. After a session's first commit, the commit shows Verified on GitHub.

To revoke: delete the key under GitHub, Settings, SSH and GPG keys, then create and seal a new one.

## Talos reader config

1. Create a client config with the `os:reader` role. This needs your admin talosconfig as the current one:

   ```bash
   talosctl config new --roles os:reader talosconfig-reader
   talosctl --talosconfig talosconfig-reader version     # works
   talosctl --talosconfig talosconfig-reader reboot -n <node>   # must fail with PermissionDenied
   ```

2. Seal it and delete the file:

   ```bash
   kubectl create secret generic claudetainer-talosconfig -n claudetainer --dry-run=client -o yaml \
       --from-file=talosconfig=talosconfig-reader \
     | kubeseal --controller-namespace sealed-secrets --controller-name sealed-secrets --format yaml \
     > argo_apps/workloads/charts/claudetainer/templates/sealedsecret-talosconfig.yaml
   rm talosconfig-reader
   ```

The certificate expires after a year, the `--crt-ttl` default. Repeat these steps before then.

## Context7 API key

1. Save the key to a file and seal it:

   ```bash
   (umask 077 && cat > context7-key)        # paste the key, press Enter, then Ctrl-D
   kubectl create secret generic claudetainer-context7 -n claudetainer --dry-run=client -o yaml \
       --from-file=api-key=context7-key \
     | kubeseal --controller-namespace sealed-secrets --controller-name sealed-secrets --format yaml \
     > argo_apps/workloads/charts/claudetainer/templates/sealedsecret-context7.yaml
   rm context7-key
   ```

2. After the pod restarts, check that the helper sees the key:

   ```bash
   kubectl -n claudetainer exec deploy/claudetainer -- /usr/local/lib/claudetainer/context7-headers.sh | jq -r keys[]
   ```

   Expected: `Authorization`. An empty `{}` means the Secret is missing, and context7 runs anonymously.

## Rotate any of them

Repeat the section, commit and push. Reloader restarts the pod when the Secret changes. Sessions resume.
