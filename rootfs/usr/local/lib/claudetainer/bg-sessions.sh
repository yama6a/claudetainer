#!/usr/bin/env bash
# Keeps scheduled sessions connected the way the server keeps claude.ai sessions connected.
#   pin <folder>     scheduled-session.sh pins the session it started there. The daemon never stops a pinned idle session
#   resume           claudetainer-start resumes each scheduled session that the last pod stop killed
#   unpin-archived   the chart's bg-unpin CronJob unpins sessions archived or deleted in claude.ai
set -euo pipefail
shopt -s nullglob

# ---- knobs ----
TRIES=50 # attempts, 0.2 s apart, to take the pins.json lock or to find a new job record

log() { printf 'bg-sessions: %s\n' "$*" >&2; }

# shellcheck source=rootfs/usr/local/lib/claudetainer/session-api.sh
source "$(dirname "$0")/session-api.sh"

JOBS="$CONFIG/jobs"
PINS="$JOBS/pins.json"
ADD='if any(.[]; . == $id) then . else . + [$id] end'
REMOVE='map(select(. != $id))'

# Claude Code's daemon takes the same lock: proper-lockfile creates the directory pins.json.lock.
edit_pins() {
  local filter="$1" id="$2" i tmp rc=0
  for ((i = 0; i < TRIES; i++)); do
    mkdir "$PINS.lock" 2> /dev/null && break
    sleep 0.2
  done
  if [ "$i" = "$TRIES" ]; then
    log "pins.json stays locked, $id not changed"
    return 1
  fi
  tmp="$(mktemp "$PINS.XXXXXX")"
  if ! { cat "$PINS" 2> /dev/null || echo '[]'; } | jq -c --arg id "$id" "$filter" > "$tmp" || ! mv "$tmp" "$PINS"; then
    rm -f "$tmp"
    rc=1
  fi
  rmdir "$PINS.lock"
  return "$rc"
}

pin() {
  local dir="$1" states short="" i
  for ((i = 0; i < TRIES; i++)); do
    states=("$JOBS"/*/state.json)
    if [ "${#states[@]}" -gt 0 ]; then
      short="$(jq -r --arg cwd "$dir" 'select(.cwd == $cwd) | .daemonShort // empty' "${states[@]}" 2> /dev/null | tail -1)"
    fi
    [ -z "$short" ] || break
    sleep 0.2
  done
  if [ -z "$short" ]; then
    log "no job record for $dir, not pinned"
    return 1
  fi
  edit_pins "$ADD" "$short"
  log "$short: pinned"
}

# No daemon runs yet at pod start, so a killed session's record still shows the state it had when the pod stopped.
resume() {
  local state short id bridge cwd status
  local -a found=()
  if ! load_token; then
    log "no valid access token, resuming no session"
    return 0
  fi
  for state in "$JOBS"/*/state.json; do
    found+=("$(jq -r 'select(.state != "done" and .state != "stopped" and .bridgeSessionId
      and (.cwd | startswith("/workspace/sessions/scheduled-")))
      | "\(.daemonShort) \(.sessionId) \(.bridgeSessionId) \(.cwd)"' "$state" 2> /dev/null || true)")
  done
  for line in "${found[@]}"; do
    [ -n "$line" ] || continue
    read -r short id bridge cwd <<< "$line"
    [ -d "$cwd" ] || continue
    status="$(session_status "$bridge")"
    if [ "$status" != active ]; then
      log "$short: $status, not resumed"
      continue
    fi
    if ! (cd "$cwd" && claude --bg --resume "$id" > /dev/null); then
      log "$short: resume failed"
      continue
    fi
    edit_pins "$ADD" "$short" || true
    log "$short: resumed"
  done
}

unpin_archived() {
  local short bridge status
  if ! load_token; then
    log "no valid access token, unpinning nothing"
    return 0
  fi
  for short in $(jq -r '.[]' "$PINS" 2> /dev/null || true); do
    bridge="$(jq -r '.bridgeSessionId // empty' "$JOBS/$short/state.json" 2> /dev/null || echo gone)"
    case "$bridge" in
      gone) status="no job record" ;;
      '') continue ;;
      *) status="$(session_status "$bridge")" ;;
    esac
    case "$status" in
      archived | deleted | "no job record")
        edit_pins "$REMOVE" "$short"
        log "$short: $status, unpinned"
        ;;
    esac
  done
}

case "${1:-}" in
  pin) pin "${2:?usage: bg-sessions.sh pin <folder>}" ;;
  resume) resume ;;
  unpin-archived) unpin_archived ;;
  *)
    echo "usage: bg-sessions.sh pin <folder> | resume | unpin-archived" >&2
    exit 1
    ;;
esac
