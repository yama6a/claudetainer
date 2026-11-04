#!/usr/bin/env bash
# Frees /workspace: folders of archived or deleted sessions, stale folders that belong to no session, and the
# cache. The chart's sweep CronJob calls it through kubectl exec once a day. The sweep-cache CronJob calls
# `sweep.sh cache` every hour, which does only the cache part.
set -euo pipefail
shopt -s nullglob

# ---- knobs ----
STALE_DAYS=30         # days without a file change before a folder that belongs to no session goes
CACHE_LIMIT_GIB=20    # /workspace/.cache is wiped whole above this
GO_BUILD_IDLE_HOURS=6 # Go build cache entries unused for this long are deleted

SESSIONS=/workspace/sessions
CACHE=/workspace/.cache

log() { printf 'sweep: %s\n' "$*" >&2; }

# shellcheck source=rootfs/usr/local/lib/claudetainer/session-api.sh
source "$(dirname "$0")/session-api.sh"

exec 9> /workspace/.sweep.lock
if ! flock -n 9; then
  log "another sweep is running"
  exit 0
fi

# The Go module cache is read-only on purpose, so rm alone fails on it.
remove() {
  chmod -R u+w "$1" 2> /dev/null || true
  rm -rf "$1"
}

# Go sets an entry's mtime when it uses the entry, at most once an hour.
prune_cache() {
  if [ -d "$CACHE/go-build" ]; then
    find "$CACHE/go-build" -ignore_readdir_race -mindepth 2 -type f -mmin +$((GO_BUILD_IDLE_HOURS * 60)) -delete
  fi
  if [ -d "$CACHE" ] && [ "$(du -sk "$CACHE" | cut -f1)" -gt $((CACHE_LIMIT_GIB * 1024 * 1024)) ]; then
    local entry
    # A running build can write into a folder while rm empties it. The next hourly run gets what stays.
    for entry in "$CACHE"/*; do remove "$entry" || log "$entry changed during the wipe, left for the next run"; done
    log "cache above $CACHE_LIMIT_GIB GiB, wiped"
  fi
}

if [ "${1:-}" = cache ]; then
  shopt -s dotglob
  prune_cache
  exit 0
fi

remove_if_stale() {
  if [ -z "$(find "$1" -mtime -"$STALE_DAYS" -print -quit)" ]; then
    remove "$1"
    log "${1#"$SESSIONS"/}: unchanged for $STALE_DAYS days, removed"
  fi
}

load_token || log "no valid access token, keeping every session folder"

# A scheduled session's folder name holds no session ID. Claude Code's job record links the folder to it.
declare -A ids
for state in "$CONFIG"/jobs/*/state.json; do
  while read -r cwd id; do
    ids[$cwd]="$id"
  done < <(jq -r 'select(.cwd and .bridgeSessionId) | "\(.cwd) \(.bridgeSessionId)"' "$state" 2> /dev/null || true)
done

declare -A statuses
found=0
for dir in "$SESSIONS"/*/; do
  dir="${dir%/}"
  name="${dir##*/}"
  case "$name" in
    home) continue ;;
    bridge-cse_*) id="${name#bridge-}" ;;
    *) id="${ids[$dir]:-}" ;;
  esac
  if [ -z "$id" ]; then
    remove_if_stale "$dir"
    continue
  fi
  [ -n "$token" ] || continue
  statuses[$dir]="$(session_status "$id")"
  case "${statuses[$dir]}" in deleted | HTTP*) ;; *) found=1 ;; esac
done

# Every session answers 404 when the token belongs to another account. A deletion counts only if one session was found.
for dir in "${!statuses[@]}"; do
  status="${statuses[$dir]}"
  if [ "$status" = archived ] || { [ "$status" = deleted ] && [ "$found" = 1 ]; }; then
    remove "$dir"
    log "${dir##*/}: $status, removed"
  elif [ "$status" != active ]; then
    log "${dir##*/}: $status, kept"
  fi
done

shopt -s dotglob
for sub in "$SESSIONS"/home/*; do remove_if_stale "$sub"; done

prune_cache
