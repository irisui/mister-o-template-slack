#!/usr/bin/env bash
#
# dream-hook.sh - Stop hook that checks dream conditions and triggers consolidation
#
# Add to settings.json:
#   "hooks": {
#     "Stop": [{
#       "type": "command",
#       "command": "bash ~/.claude/skills/dream/dream-hook.sh"
#     }]
#   }
#
# Fires when a Claude Code session ends. Checks if 24hrs + 5 sessions
# have passed since last dream. If so, spawns claude in the background
# to run /dream. Zero overhead when conditions aren't met (~10ms check).

SKILL_DIR="$HOME/.claude/skills/dream"
LOCK_FILE="$SKILL_DIR/.dream.lock"

# Anti-overlap guard (fix 2026-09-03): without this, rapid consecutive Stop
# events (e.g. a 1-minute loop) can all pass should-dream.sh before the first
# run finishes writing its .last-dream, spawning dozens of parallel `claude -p`
# runs and burning through the session's token limit.
if [[ -f "$LOCK_FILE" ]]; then
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$LOCK_PID" ]] && kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "Dream already running (PID $LOCK_PID) - skipping"
        exit 0
    fi
    rm -f "$LOCK_FILE"  # stale lock, process is gone
fi

# Run the condition check
if bash "$SKILL_DIR/should-dream.sh" 2>/dev/null; then
    # Mark "just ran" immediately, before spawning, so a Stop event firing a
    # few seconds later (before the background run finishes) sees a fresh
    # timestamp right away instead of re-triggering.
    LAST_DREAM_FILE=""
    for dir in "$HOME/.claude/projects/"*/memory/; do
        if [[ -f "$dir/.last-dream" ]]; then
            LAST_DREAM_FILE="$dir/.last-dream"
            break
        fi
    done
    if [[ -z "$LAST_DREAM_FILE" ]]; then
        # First run ever - create the marker in the first available project memory dir
        for dir in "$HOME/.claude/projects/"*/memory/; do
            LAST_DREAM_FILE="$dir/.last-dream"
            break
        done
    fi
    [[ -n "$LAST_DREAM_FILE" ]] && date +%s > "$LAST_DREAM_FILE"

    # Conditions met - spawn dream in background
    # Use claude -p to run the dream skill non-interactively
    nohup claude -p "Run the dream memory consolidation skill. Read ~/.claude/skills/dream/SKILL.md and execute all 4 phases for all projects." \
        --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
        > /tmp/dream-$(date +%Y%m%d-%H%M%S).log 2>&1 &

    DREAM_PID=$!
    echo "$DREAM_PID" > "$LOCK_FILE"
    echo "Dream consolidation started in background (PID: $DREAM_PID)"

    ( wait "$DREAM_PID" 2>/dev/null; rm -f "$LOCK_FILE" ) &
    disown
fi

# Always exit 0 so we don't block the session from closing
exit 0
