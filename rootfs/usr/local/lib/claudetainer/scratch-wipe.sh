#!/usr/bin/env bash
# CronJob body: deletes every top-level object in the scratch namespace older than MAX_AGE_DAYS.
# Garbage collection removes the children, so objects with an owner are left alone.
set -uo pipefail

: "${SCRATCH_NAMESPACE:?}" "${MAX_AGE_DAYS:?}"

cutoff="$(date -u -d "-${MAX_AGE_DAYS} days" +%Y-%m-%dT%H:%M:%SZ)"
failed=0

# Argo CD tracks by annotation here, so that annotation marks what the chart owns.
select_stale='
  .items[]
  | select(.metadata.creationTimestamp < $cutoff)
  | select((.metadata.ownerReferences // []) | length == 0)
  | select(.metadata.annotations["argocd.argoproj.io/tracking-id"] == null)
  | select((.kind == "ConfigMap" and .metadata.name == "kube-root-ca.crt") | not)
  | select((.kind == "ServiceAccount" and .metadata.name == "default") | not)
  | .metadata.name'

while IFS= read -r kind; do
  case "$kind" in events | events.events.k8s.io | endpoints | endpointslices.discovery.k8s.io) continue ;; esac
  if ! names="$(kubectl get "$kind" -n "$SCRATCH_NAMESPACE" -o json | jq -r --arg cutoff "$cutoff" "$select_stale")"; then
    echo "cannot list $kind" >&2
    failed=1
    continue
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    echo "deleting $kind/$name"
    kubectl delete "$kind" "$name" -n "$SCRATCH_NAMESPACE" --wait=false || failed=1
  done <<< "$names"
done < <(kubectl api-resources --namespaced --verbs=list,delete -o name)

exit "$failed"
