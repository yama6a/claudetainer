#!/usr/bin/env bash
# Sourced by sweep.sh, bg-sessions.sh and wake.sh. Asks claude.ai for a session's state, or sends it a message.
# The caller defines log().

# ---- knobs ----
API=https://api.anthropic.com # where claude.ai answers for a session

CONFIG="${CLAUDE_CONFIG_DIR:-/home/agent/.claude}"

# The running claude process refreshes this token. A refresh here would spend the refresh token, which works once.
load_token() {
  local creds="$CONFIG/.credentials.json"
  token=""
  if [ -r "$creds" ] && [ "$(jq -r '.claudeAiOauth.expiresAt // 0' "$creds")" -gt $((($(date +%s) + 300) * 1000)) ]; then
    token="$(jq -r '.claudeAiOauth.accessToken' "$creds")"
  fi
  [ -n "$token" ]
}

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

# Undocumented: the endpoint claude.ai posts a typed message to. The session sees the message as sent by another
# session, so it never takes it as the user's answer. Prints the HTTP status.
post_message() {
  local body
  body="$(jq -nc --arg uuid "$(cat /proc/sys/kernel/random/uuid)" --arg text "$2" \
    '{events: [{payload: {type: "user", uuid: $uuid, message: {role: "user", content: $text}}}]}')"
  curl -sS -m 15 -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $token" \
    -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' -d "$body" \
    "$API/v1/code/sessions/${1/#session_/cse_}/events" || echo 000
}
