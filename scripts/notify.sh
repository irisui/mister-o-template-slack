#!/usr/bin/env bash
# Leveled Slack notifier. Reuses the existing .env credentials.
# Usage: notify.sh <info|warning|red> <message>
# Never fails hard: a notify problem must not take down the agent or supervisor.
set -uo pipefail

level="${1:-info}"
message="${2:-}"

ENV_FILE="${ENV_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env}"
CONFIG_FILE="${CONFIG_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.json}"
CURL_BIN="${CURL_BIN:-curl}"

case "$level" in
  info)    prefix="ℹ️" ;;
  warning) prefix="⚠️" ;;
  red)     prefix="🔴" ;;
  *)       prefix="ℹ️" ;;
esac

unset SLACK_BOT_TOKEN SLACK_CHANNEL_ID
# shellcheck disable=SC1090
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

token="${SLACK_BOT_TOKEN:-}"
channel=""
if [[ -f "$CONFIG_FILE" ]]; then
  channel="$(jq -r '.supervisor.test_slack_channel_id // empty' "$CONFIG_FILE" 2>/dev/null || true)"
fi
[[ -z "$channel" ]] && channel="${SLACK_CHANNEL_ID:-}"

# If ENV_FILE is absent or lacks creds, token/channel stay empty and we skip
# silently (non-fatal by design). The stderr line below shows in supervisor logs.
if [[ -z "$token" || -z "$channel" ]]; then
  echo "notify: missing token or channel, skipping (level=$level)" >&2
  exit 0
fi

# Written to a temp file and sent with --data-binary @file rather than as a command-line
# argument: curl is a native Windows binary, and MSYS bash mangles non-ASCII (diacritics,
# em dashes) when converting argv for a native exec. A file bypasses that conversion.
JSON_FILE="$(mktemp)"
jq -nc --arg ch "$channel" --arg txt "${prefix} ${message}" '{channel: $ch, text: $txt}' > "$JSON_FILE"
"$CURL_BIN" -s -X POST "https://slack.com/api/chat.postMessage" \
  -H "Authorization: Bearer ${token}" \
  -H "Content-type: application/json; charset=utf-8" \
  --data-binary "@$JSON_FILE" \
  >/dev/null 2>&1 || true
rm -f "$JSON_FILE"
exit 0
