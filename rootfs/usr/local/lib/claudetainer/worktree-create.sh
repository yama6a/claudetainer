#!/usr/bin/env bash
# WorktreeCreate hook. Claude Code reads the folder path from the last line of stdout, so all else goes to stderr.
set -euo pipefail

SESSIONS=/workspace/sessions

input="$(cat)"
name="$(jq -r '.name // empty' <<< "$input")"
cwd="$(jq -r '.cwd // empty' <<< "$input")"

case "$name" in
  '' | */* | .*)
    echo "worktree-create: unusable worktree name '$name'" >&2
    exit 1
    ;;
  # Remote Control sessions. The server asks again with the same name on every resume, so reuse the folder.
  bridge-*)
    dir="$SESSIONS/$name"
    mkdir -p "$dir"
    setsid /usr/local/lib/claudetainer/sweep.sh > /dev/null 2>&1 < /dev/null &
    ;;
  # A hook replaces git worktrees for every caller, so subagent isolation gets the git worktree it expects.
  *)
    root="$(git -C "$cwd" rev-parse --show-toplevel)"
    dir="$root/.claude/worktrees/$name"
    if [ ! -d "$dir" ]; then
      git -C "$root" worktree add -q -b "worktree-$name" "$dir" HEAD >&2
    fi
    ;;
esac

printf '%s\n' "$dir"
