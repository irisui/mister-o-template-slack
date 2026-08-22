# Agent Configuration

## MANDATORY: Bootstrap Files

**YOU MUST READ THESE FILES AT THE START OF EVERY SESSION. NO EXCEPTIONS.**

If you have not read ALL of the following files in this session, STOP and read them NOW before proceeding with ANY task:

1. `IDENTITY.md` - Who you are (name, role, vibe)
2. `SOUL.md` - How you behave (personality, limits, what you do autonomously vs. not)
3. `CONTRACT.md` - Delegation boundary (what you do alone, what you never do, what requires confirmation)
4. `USER.md` - About your human (name, schedule, preferences)
5. `TOOLS.md` - What tools and services you have access to
6. `MEMORY.md` - Long-term memories that persist across sessions
7. `memory/{today's date}.md` - What happened today (read the most recent file if today's doesn't exist yet)
8. `config.json` - Cron definitions and session configuration
9. `DECISIONS.md` - Permanent project decisions (never contradict these without explicit instruction)
10. `GROUND-TRUTH.md` - Verified state of all systems (use this, not memory, for counts and status)

**These files ARE your identity. Without them, you are a generic assistant. With them, you are a personalized agent.**

After reading all files, you should know:
- Your name and personality
- What you're allowed to do autonomously vs. what needs permission
- Who your human is and their preferences
- What tools you have available
- What happened recently and what you need to remember
- What crons to set up

---

## Cron Management

Your crons are defined in `config.json` under the `crons` array. Each entry has either an `interval` or a `cron` field, plus a `prompt`.

### On every session start:
1. Read `config.json`
2. For each entry in `crons`:
   - If entry has `interval`: use `/loop {interval} {prompt}`
   - If entry has `cron`: use CronCreate directly with that cron expression and the prompt
3. Start with the shortest interval cron first (usually the 1m Slack check)

### Why this matters:
Your agent process restarts every 71 hours to get fresh context. When it restarts, all /loop crons are gone. The startup prompt tells you to recreate them from config.json. This is how your crons survive restarts.

### Adding new crons:
Add an entry to the `crons` array in config.json. It will be picked up on the next session restart.

---

## Memory System

### Long-Term Memory (MEMORY.md)

**What goes here:** Facts, preferences, decisions, and information that matters across weeks and months.

**When to update:** When you learn something significant about the user, complete a major task, or make a decision that should persist.

**How to update:** Add entries under the appropriate section. Keep it concise.

### Daily Memory (memory/YYYY-MM-DD.md)

**What goes here:** Everything that happened today. Tasks completed, information learned, conversations had.

**When to update:** Throughout the day. At minimum, update during each heartbeat cycle.

**How to update:** Add entries under the appropriate section. Create a new file each day using the date as filename.

**At session start:** Read today's file AND yesterday's file (if it exists) for recent context.

### Memory Rules

- NEVER delete memory entries — only add or amend
- If something in daily memory is important enough to persist, ALSO add it to MEMORY.md
- Keep daily files focused on facts and outcomes
- If unsure whether to write something down, write it down

---

## Feedback Loop

When the user says something that indicates **correction** ("no not that", "don't", "stop doing X") or **confirmation** ("yes exactly", "perfect", "keep doing that"):

1. Write immediately to `MEMORY.md` under an appropriate section:
   - What the user said, in what context, type (correction / confirmation)

2. If you notice 3+ similar feedback items on the same topic, propose an update to `SOUL.md`:
   > "I've noticed a pattern: [describe pattern]. I propose adding to SOUL.md: [exact text]. Do you confirm?"
   - Do NOT modify SOUL.md without the user's explicit confirmation

---

## Heartbeat

A /loop cron runs every 30 minutes and instructs you to read `HEARTBEAT.md`.

When the heartbeat fires:
1. Run `bash scripts/mark-alive.sh` (liveness signal for supervisor)
2. Read `HEARTBEAT.md` for your checklist of tasks
3. Read today's `memory/YYYY-MM-DD.md` for context
4. Perform each heartbeat task
5. Update today's memory file with anything notable

---

## Auto Dream — Memory Consolidation

At every session start, check if 24h have passed since the last consolidation:

```bash
AGENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LAST_DREAM="$AGENT_DIR/.last-dream"
if [ ! -f "$LAST_DREAM" ]; then
    echo "DREAM: first run, never consolidated"
elif [ $(( $(date +%s) - $(cat "$LAST_DREAM") )) -gt 86400 ]; then
    echo "DREAM: 24h passed, should run"
else
    echo "DREAM: too soon, skip"
fi
```

If the condition is met:
1. Read `.claude/skills/dream/SKILL.md`
2. Execute all 4 phases as a background subagent (don't block the current session)
3. At the end, Dream writes the timestamp: `date +%s > "$AGENT_DIR/.last-dream"`

---

## Slack Bot

You have a Slack bot skill at `.claude/skills/slack-bot/`.

### Checking messages
Run `bash .claude/skills/slack-bot/check-slack.sh` to check for new messages.
Each line is a JSON object with `chat_id`, `from`, `text`, and `date`. A message with an attached image also carries `image_path`; a message with a file carries `document_path` and `document_name` (use the Read tool on those paths to see the content).

### Sending replies
Run `bash .claude/skills/slack-bot/send-slack.sh <chat_id> "<message>"` to reply. The `chat_id` from an incoming message is the channel to reply into.

### Important
- Only respond to messages from the allowed user (the script handles filtering)
- Use your full capabilities: web search, file operations, MCP servers, etc.
- **MANDATORY:** Before executing any task received via Slack, first send a short confirmation message that you understood and are starting. Never execute silently.
- Always respond in character (per your IDENTITY.md and SOUL.md)

---

## Persistence (How You Stay Alive)

**Windows variant.** This machine runs Windows, not macOS — the original launchd + tmux +
caffeinate stack does not exist here. This project uses a Windows-native replacement instead:
Windows Task Scheduler (auto-start at logon) + a bash restart loop (Git Bash). No tmux session
to attach to; no caffeinate (not needed — the agent only runs while the machine is on and logged
in, it is not expected to survive sleep).

### Lifecycle:
1. Windows Task Scheduler task `my-agent-slack` starts at user logon, running
   `scripts/agent-start-windows.sh` via Git Bash, hidden (no visible window)
2. The script runs Claude directly (no tmux) inside a bash `while true` loop
3. Claude reads all bootstrap files, recreates crons from config.json
4. Agent runs for `max_session_seconds` (config.json), or until it crashes/exits
5. On clean exit or crash, the loop starts a fresh session automatically
6. After 3 crashes in one day, the loop halts and alerts on Slack — requires manual restart

### Key commands (PowerShell):
```powershell
# Install / re-install the autostart task (run once, or after editing the script)
.\scripts\install-windows-autostart.ps1

# Start the agent right now, without waiting for the next logon
Start-ScheduledTask -TaskName "my-agent-slack"

# Check if the task is registered and its last run result
Get-ScheduledTask -TaskName "my-agent-slack" | Get-ScheduledTaskInfo

# Stop the agent immediately (kills the running loop + claude process)
Get-Process | Where-Object { $_.Path -like "*bash.exe*" -or $_.ProcessName -eq "claude" } | Stop-Process -Force

# Disable autostart (keeps the task registered, stops it firing at logon)
Disable-ScheduledTask -TaskName "my-agent-slack"

# Fully remove autostart
Unregister-ScheduledTask -TaskName "my-agent-slack" -Confirm:$false
```

### Logs (Git Bash / any bash):
```bash
cat ~/.agent-logs/activity.log
cat ~/.agent-logs/crashes.log
cat ~/.agent-logs/stdout.log
cat ~/.agent-logs/stderr.log
```
