#!/usr/bin/env bash
# headersHelper of the context7 plugin: the API key reaches the request header from the Secret file, never from
# the environment. Without the file, context7 runs anonymously at a lower rate limit.
set -euo pipefail

KEY_FILE=/etc/claudetainer/secrets/context7/api-key

if [ -s "$KEY_FILE" ]; then
  jq -cn --rawfile key "$KEY_FILE" '{Authorization: ($key | rtrimstr("\n"))}'
else
  echo '{}'
fi
