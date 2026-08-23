#!/bin/bash
# Send a message to a Slack channel.
# Usage: bash .claude/skills/slack-bot/send-slack.sh <channel_id> "<message>"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../../.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

BOT_TOKEN="${SLACK_BOT_TOKEN}"
CHANNEL="$1"
MESSAGE="$2"

if [ -z "$BOT_TOKEN" ]; then
  echo "ERROR: SLACK_BOT_TOKEN not set"
  exit 1
fi

if [ -z "$CHANNEL" ] || [ -z "$MESSAGE" ]; then
  echo "Usage: send-slack.sh <channel_id> \"<message>\""
  exit 1
fi

# Build the JSON body with jq so quotes, newlines and unicode in the message are safe.
RESPONSE=$(curl -s -X POST "https://slack.com/api/chat.postMessage" \
  -H "Authorization: Bearer ${BOT_TOKEN}" \
  -H "Content-type: application/json; charset=utf-8" \
  --data "$(jq -nc --arg ch "$CHANNEL" --arg txt "$MESSAGE" '{channel: $ch, text: $txt}')")

# Check for errors
if echo "$RESPONSE" | jq -e '.ok == true' > /dev/null 2>&1; then
  echo "Message sent successfully"
else
  echo "ERROR: Failed to send message:"
  echo "$RESPONSE" | jq -r '.error'
  exit 1
fi
