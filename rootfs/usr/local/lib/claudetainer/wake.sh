#!/usr/bin/env bash
# Wakes the claude.ai sessions that were busy when the pod stopped. After a restart the server starts a session
# only once claude.ai sends it something. Claude Code then resumes a cut-off turn and lost background tasks itself.
#   save   the chart's preStop hook copies each live session's status. Claude Code deletes it on a clean exit
#   run    claudetainer-start runs it in the background. It messages each session that was busy at the stop
set -euo pipefail
shopt -s nullglob

# ---- knobs ----
TRIES=60  # attempts, 2 s apart, to see the server register with claude.ai
SETTLE=10 # seconds to wait after the server registers, before the first message
MESSAGE="The claudetainer pod restarted, and your last turn or your background tasks stopped. Check what they changed before you run anything again. Do not answer open questions on behalf of the user."

log() { printf 'wake: %s\n' "$*" >&2; }

# shellcheck source=rootfs/usr/local/lib/claudetainer/session-api.sh
source "$(dirname "$0")/session-api.sh"

RECORDS="$CONFIG/sessions"
SAVED="$CONFIG/.claudetainer-stopped.json"
STARTED="$CONFIG/.claudetainer-started-at"
# The server writes this when it registers. The folder name follows SERVER_DIR in claudetainer-start.
POINTER="$CONFIG/projects/-workspace-sessions-home/bridge-pointer.json"
SESSION_FILTER='select(.kind == "interactive" and .bridgeSessionId)'

# A record's pid can belong to another process after a restart, so its start time must match too.
alive() {
  local pid start stat
  read -r pid start < <(jq -r '"\(.pid) \(.procStart)"' "$1" 2> /dev/null) || return 1
  stat="$(cat "/proc/$pid/stat" 2> /dev/null)" || return 1
  stat="${stat##*) }"
  read -ra stat <<< "$stat"
  [ "${stat[19]}" = "$start" ]
}

running() {
  local f
  for f in "$RECORDS"/*.json; do
    jq -e --arg id "$1" 'select(.bridgeSessionId == $id)' "$f" > /dev/null 2>&1 && alive "$f" && return 0
  done
  return 1
}

save() {
  local f tmp
  local -a live=()
  for f in "$RECORDS"/*.json; do
    if alive "$f"; then live+=("$f"); fi
  done
  tmp="$(mktemp "$SAVED.XXXXXX")"
  if [ "${#live[@]}" -gt 0 ]; then
    jq -s "[.[] | $SESSION_FILTER | {bridgeSessionId, status}]" "${live[@]}" > "$tmp"
  else
    echo '[]' > "$tmp"
  fi
  mv "$tmp" "$SAVED"
  log "saved the status of $(jq length "$SAVED") sessions"
}

# Without a saved copy the pod did not stop cleanly. Then the records of its dead processes are still there.
busy_at_stop() {
  local since="$1"
  local -a records=("$RECORDS"/*.json)
  if [ -s "$SAVED" ]; then
    jq -r '.[] | select(.status == "busy") | .bridgeSessionId' "$SAVED" 2> /dev/null || true
  elif [ "$since" -gt 0 ] && [ "${#records[@]}" -gt 0 ]; then
    jq -r --argjson t "$since" "$SESSION_FILTER | select(.status == \"busy\" and .startedAt >= \$t) | .bridgeSessionId" \
      "${records[@]}" 2> /dev/null || true
  fi
}

run() {
  local now prev ids id status code i
  now="$(date +%s)"
  prev="$(cat "$STARTED" 2> /dev/null || echo 0)"
  echo "$((now * 1000))" > "$STARTED"
  ids="$(busy_at_stop "$prev" | sort -u)"
  rm -f "$SAVED"
  if [ -z "$ids" ]; then
    log "no session was busy at the stop"
    return 0
  fi
  for ((i = 0; i < TRIES; i++)); do
    [ "$(stat -c %Y "$POINTER" 2> /dev/null || echo 0)" -lt "$now" ] || break
    sleep 2
  done
  if [ "$i" = "$TRIES" ]; then
    log "the server did not register, waking no session"
    return 0
  fi
  sleep "$SETTLE"
  if ! load_token; then
    log "no valid access token, waking no session"
    return 0
  fi
  for id in $ids; do
    if running "$id"; then
      log "$id: already running"
      continue
    fi
    status="$(session_status "$id")"
    case "$status" in
      archived | deleted)
        log "$id: $status, not woken"
        continue
        ;;
    esac
    code="$(post_message "$id" "$MESSAGE")"
    case "$code" in
      200) log "$id: woken" ;;
      *) log "$id: wake failed with HTTP $code" ;;
    esac
  done
}

case "${1:-}" in
  save) save ;;
  run) run ;;
  *)
    echo "usage: wake.sh save | run" >&2
    exit 1
    ;;
esac
