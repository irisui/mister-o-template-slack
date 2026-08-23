#!/bin/bash
# Check for new Slack messages from the allowed user in the configured channel.
# Usage: bash .claude/skills/slack-bot/check-slack.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../../.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

BOT_TOKEN="${SLACK_BOT_TOKEN}"
CHANNEL_ID="${SLACK_CHANNEL_ID}"
ALLOWED_USER="${SLACK_ALLOWED_USER}"   # Your Slack user ID (U...) - set in .env
TS_FILE="$HOME/.claude-slack-ts"

if [ -z "$BOT_TOKEN" ]; then
  echo "ERROR: SLACK_BOT_TOKEN not set. Add to .env:"
  echo '  SLACK_BOT_TOKEN="xoxb-your-bot-token"'
  exit 1
fi

if [ -z "$CHANNEL_ID" ]; then
  echo "ERROR: SLACK_CHANNEL_ID not set. Add to .env:"
  echo '  SLACK_CHANNEL_ID="C0XXXXXXX"'
  exit 1
fi

if [ -z "$ALLOWED_USER" ]; then
  echo "ERROR: SLACK_ALLOWED_USER not set. Add to .env:"
  echo '  SLACK_ALLOWED_USER="U0XXXXXXX"'
  echo 'Find it: Slack -> your avatar -> Profile -> three dots -> Copy member ID'
  exit 1
fi

# First run: no offset yet. Bootstrap to "now" so we only ever process messages from
# this point forward, never the entire channel backlog (Slack would return all history).
if [ ! -f "$TS_FILE" ]; then
  date +%s > "$TS_FILE"
  exit 0
fi

LAST_TS=$(cat "$TS_FILE" 2>/dev/null || echo "0")

# Fetch messages strictly newer than LAST_TS. --max-time caps the whole request so a
# stalled TCP connection can't hang the comms tick and deafen every later poll.
RESPONSE=$(curl -s --max-time 15 \
  -H "Authorization: Bearer ${BOT_TOKEN}" \
  --get "https://slack.com/api/conversations.history" \
  --data-urlencode "channel=${CHANNEL_ID}" \
  --data-urlencode "oldest=${LAST_TS}" \
  --data-urlencode "inclusive=false" \
  --data-urlencode "limit=50")

# A timed-out / failed poll yields empty output: treat as "no messages this tick" and
# exit cleanly without touching the offset, so the next tick simply retries.
if [ -z "$RESPONSE" ]; then
  exit 0
fi

# Check for API errors (bad token, bot not in channel, etc.)
if echo "$RESPONSE" | jq -e '.ok == false' > /dev/null 2>&1; then
  echo "ERROR: Slack API returned error:"
  echo "$RESPONSE" | jq -r '.error'
  exit 1
fi

# Advance the offset to the newest ts in the raw batch (before filtering), so a message
# from someone else still moves us forward and we never re-fetch the same window.
NEW_TS=$(echo "$RESPONSE" | jq -r '.messages[0].ts // empty')
if [ -n "$NEW_TS" ]; then
  echo "$NEW_TS" > "$TS_FILE"
fi

# Slack returns newest-first; reverse to chronological order. Keep only real messages
# from the allowed user: drop bot echoes and system subtypes, but keep file shares.
MESSAGES=$(echo "$RESPONSE" | jq --arg uid "$ALLOWED_USER" \
  '[.messages[] | select(.user == $uid and (.bot_id == null) and ((has("subtype") | not) or .subtype == "file_share"))] | reverse')

MSG_COUNT=$(echo "$MESSAGES" | jq 'length')
if [ "$MSG_COUNT" -gt 0 ]; then
  echo "$MESSAGES" | jq -c '.[]' | while IFS= read -r msg; do
    HAS_FILE=$(echo "$msg" | jq -r 'if (.files | length // 0) > 0 then "yes" else "no" end')

    if [ "$HAS_FILE" = "yes" ]; then
      # Slack file: url_private requires the bot token to download.
      FILE_URL=$(echo "$msg" | jq -r '.files[0].url_private // ""')
      FILE_NAME=$(echo "$msg" | jq -r '.files[0].name // "file"')
      MIMETYPE=$(echo "$msg" | jq -r '.files[0].mimetype // ""')
      SAFE_NAME=$(echo "$FILE_NAME" | sed 's/[^A-Za-z0-9._-]/-/g')

      if [ -n "$FILE_URL" ]; then
        case "$MIMETYPE" in
          image/*)
            LOCAL_PATH="/tmp/slack-photo-$(date +%s)-${SAFE_NAME}"
            curl -s --max-time 60 -H "Authorization: Bearer ${BOT_TOKEN}" "$FILE_URL" -o "$LOCAL_PATH"
            echo "$msg" | jq -c --arg chan "$CHANNEL_ID" --arg path "$LOCAL_PATH" '{
              chat_id: $chan,
              from: .user,
              text: (.text // ""),
              image_path: $path,
              date: (.ts | split(".")[0] | tonumber)
            }'
            ;;
          *)
            LOCAL_PATH="/tmp/slack-doc-$(date +%s)-${SAFE_NAME}"
            curl -s --max-time 60 -H "Authorization: Bearer ${BOT_TOKEN}" "$FILE_URL" -o "$LOCAL_PATH"
            echo "$msg" | jq -c --arg chan "$CHANNEL_ID" --arg path "$LOCAL_PATH" --arg dn "$FILE_NAME" '{
              chat_id: $chan,
              from: .user,
              text: (.text // ""),
              document_path: $path,
              document_name: $dn,
              date: (.ts | split(".")[0] | tonumber)
            }'
            ;;
        esac
      fi
    else
      # Text message. Never emit a bare null text so nothing is silently lost.
      echo "$msg" | jq -c --arg chan "$CHANNEL_ID" '{
        chat_id: $chan,
        from: .user,
        text: (.text // "(mesaj fara continut text)"),
        date: (.ts | split(".")[0] | tonumber)
      }'
    fi
  done
fi
