#!/usr/bin/env bash
# Starts a background session with Remote Control on, in a new folder, with the prompt read from stdin.
# The chart's scheduled-session CronJobs call it through kubectl exec.
set -euo pipefail

SESSIONS=/workspace/sessions

name="${1:-}"
case "$name" in
  '' | *[!a-z0-9-]*)
    echo "scheduled-session: usage: scheduled-session.sh <name matching [a-z0-9-]+> < prompt" >&2
    exit 1
    ;;
esac
prompt="$(cat)"
if [ -z "$prompt" ]; then
  echo "scheduled-session: no prompt on stdin" >&2
  exit 1
fi

# kubectl exec skips claudetainer-start, which unsets these. Claude and nvm need them absent.
unset BASH_ENV CLAUDE_ENV_FILE NPM_CONFIG_PREFIX

stamp="$(date -u +%Y-%m-%d-%H%M)"
dir="$SESSIONS/scheduled-$name-$stamp"
mkdir -p "$dir"
cd "$dir"
exec claude --bg --remote-control "$name $stamp" --permission-mode bypassPermissions "$prompt"
