#!/usr/bin/env bash
# Frees /workspace: folders of archived or deleted sessions, stale folders that belong to no session, and an
# oversized cache. The chart's sweep CronJob calls it through kubectl exec once a day.
set -euo pipefail
shopt -s nullglob

# ---- knobs ----
STALE_DAYS=30                 # days without a file change before a folder that belongs to no session goes
CACHE_LIMIT_GIB=20            # /workspace/.cache is wiped whole above this
API=https://api.anthropic.com # where claude.ai answers for a session's state

SESSIONS=/workspace/sessions
CACHE=/workspace/.cache
CONFIG="${CLAUDE_CONFIG_DIR:-/home/agent/.claude}"

log() { printf 'sweep: %s\n' "$*" >&2; }

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

remove_if_stale() {
  if [ -z "$(find "$1" -mtime -"$STALE_DAYS" -print -quit)" ]; then
    remove "$1"
    log "${1#"$SESSIONS"/}: unchanged for $STALE_DAYS days, removed"
  fi
}

# The running claude process refreshes this token. A refresh here would spend the refresh token, which works once.
token=""
creds="$CONFIG/.credentials.json"
if [ -r "$creds" ] && [ "$(jq -r '.claudeAiOauth.expiresAt // 0' "$creds")" -gt $((($(date +%s) + 300) * 1000)) ]; then
  token="$(jq -r '.claudeAiOauth.accessToken' "$creds")"
else
  log "no valid access token, keeping every session folder"
fi

# Undocumented: the endpoint Claude Code itself reads. Prints the session's status, or "deleted" on a 404.
session_status() {
  local body code
  body="$(mktemp)"
  code="$(curl -sS -m 15 -o "$body" -w '%{http_code}' -H "Authorization: Bearer $token" \
    -H 'anthropic-version: 2023-06-01' "$API/v1/code/sessions/$1")" || code=000
  case "$code" in
    200) jq -r '.response_shape.status // empty' "$body" 2> /dev/null || echo "unreadable answer" ;;
    404) echo deleted ;;
    *) echo "HTTP $code" ;;
  esac
  rm -f "$body"
}

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

if [ -d "$CACHE" ] && [ "$(du -sk "$CACHE" | cut -f1)" -gt $((CACHE_LIMIT_GIB * 1024 * 1024)) ]; then
  for entry in "$CACHE"/*; do remove "$entry"; done
  log "cache above $CACHE_LIMIT_GIB GiB, wiped"
fi
