#!/usr/bin/env bash
# Frees /workspace: stale session folders, stale subfolders of the home session, and an oversized cache.
set -euo pipefail

# ---- knobs ----
STALE_DAYS=30       # days without a transcript write (sessions) or a file change (home subfolders)
CACHE_LIMIT_GIB=20  # /workspace/.cache is wiped whole above this
MIN_INTERVAL_MIN=60 # the WorktreeCreate hook starts a sweep per new session, so rate-limit the scans

SESSIONS=/workspace/sessions
CACHE=/workspace/.cache
PROJECTS="${CLAUDE_CONFIG_DIR:-/home/agent/.claude}/projects"

exec 9> /workspace/.sweep.lock
flock -n 9 || exit 0
stamp=/workspace/.sweep.stamp
if [ -n "$(find "$stamp" -mmin -"$MIN_INTERVAL_MIN" 2> /dev/null)" ]; then exit 0; fi
touch "$stamp"

# The Go module cache is read-only on purpose, so rm alone fails on it.
remove() {
  chmod -R u+w "$1" 2> /dev/null || true
  rm -rf "$1"
}

# Claude Code names a transcript folder after the working directory, every non-alphanumeric turned into '-'.
for dir in "$SESSIONS"/*/; do
  dir="${dir%/}"
  [ "${dir##*/}" = home ] && continue
  project="$PROJECTS/$(printf '%s' "$dir" | sed 's/[^A-Za-z0-9]/-/g')"
  if [ -d "$project" ]; then
    recent="$(find "$project" -name '*.jsonl' -mtime -"$STALE_DAYS" -print -quit)"
  else
    recent="$(find "$dir" -maxdepth 0 -mtime -"$STALE_DAYS" -print -quit)"
  fi
  [ -n "$recent" ] || remove "$dir"
done

shopt -s dotglob nullglob
for sub in "$SESSIONS"/home/*; do
  [ -n "$(find "$sub" -mtime -"$STALE_DAYS" -print -quit)" ] || remove "$sub"
done

if [ -d "$CACHE" ] && [ "$(du -sk "$CACHE" | cut -f1)" -gt $((CACHE_LIMIT_GIB * 1024 * 1024)) ]; then
  for entry in "$CACHE"/*; do remove "$entry"; done
fi
