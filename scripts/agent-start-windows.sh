#!/usr/bin/env bash
# agent-start-windows.sh - Ține agentul pornit pe Windows, fără macOS launchd/tmux/caffeinate.
#
# Rulat de Windows Task Scheduler la logon (vezi scripts/install-windows-autostart.ps1),
# sau manual dintr-un terminal Git Bash. Rulează în buclă: dacă sesiunea Claude Code
# se termină curat sau crapă neașteptat, pornește alta, până oprești task-ul sau
# închizi fereastra (dacă a fost pornit manual).
#
# Ce înlocuiește din tripleta macOS:
#   - launchd (auto-start la login, auto-restart)  -> Windows Task Scheduler (trigger "at logon")
#   - tmux (sesiune persistentă cu PTY)             -> nu mai e nevoie; fereastra/consola oferă PTY-ul
#   - caffeinate (previne sleep)                    -> nu mai e nevoie când rulează doar cât laptopul e pornit
#
# Ce păstrează din agent-wrapper.sh original:
#   - auto-restart la crash neașteptat
#   - limită de 3 crash-uri/zi (apoi halt + alertă Slack, cere restart manual al task-ului)
#   - clasificare a ieșirii: timeout de sesiune curat vs. rate-limit vs. crash real
#
# Usage: bash scripts/agent-start-windows.sh [project_dir]

set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_DIR="${HOME}/.agent-logs"
CRASH_LOG="${LOG_DIR}/crashes.log"
CRASH_COUNT_FILE="${LOG_DIR}/.crash_count_today"
MAX_CRASHES_PER_DAY=3

mkdir -p "${LOG_DIR}"

# --- Config ---
if [[ -f "${PROJECT_DIR}/.env" ]]; then
    set -a
    source "${PROJECT_DIR}/.env"
    set +a
fi

CONFIG_FILE="${PROJECT_DIR}/config.json"
MAX_SESSION=$(jq -r '.max_session_seconds // 255600' "${CONFIG_FILE}" 2>/dev/null || echo "255600")
STARTUP_PROMPT="You are starting a new session. Read all bootstrap files listed in CLAUDE.md. Then read config.json and set up your crons using /loop for each entry in the crons array. Start with the comms cron (1m) first. After crons are set up, send a Slack message to the user saying you're back online and what you're about to work on."

cd "${PROJECT_DIR}"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) agent-start-windows.sh launched (project: ${PROJECT_DIR})" >> "${LOG_DIR}/activity.log"

while true; do
    TODAY=$(date +%Y-%m-%d)
    if [[ -f "${CRASH_COUNT_FILE}" ]]; then
        STORED_DATE=$(cut -d: -f1 "${CRASH_COUNT_FILE}" 2>/dev/null || echo "")
        CRASH_COUNT=$(cut -d: -f2 "${CRASH_COUNT_FILE}" 2>/dev/null || echo "0")
    else
        STORED_DATE=""
        CRASH_COUNT=0
    fi
    [[ "${STORED_DATE}" != "${TODAY}" ]] && CRASH_COUNT=0

    if [[ ${CRASH_COUNT} -ge ${MAX_CRASHES_PER_DAY} ]]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) HALTED: exceeded ${MAX_CRASHES_PER_DAY} crashes today. Manual restart required." >> "${CRASH_LOG}"

        if [[ -n "${SLACK_BOT_TOKEN:-}" && -n "${SLACK_CHANNEL_ID:-}" ]]; then
            ALERT_TEXT="ALERT: Agentul a crapat de ${MAX_CRASHES_PER_DAY} ori azi si s-a oprit. Reporneste task-ul din Task Scheduler (my-agent) cand esti gata, sau redeschide laptopul maine."
            curl -s -X POST "https://slack.com/api/chat.postMessage" \
                -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
                -H "Content-type: application/json; charset=utf-8" \
                --data "$(jq -nc --arg ch "${SLACK_CHANNEL_ID}" --arg txt "${ALERT_TEXT}" '{channel: $ch, text: $txt}')" \
                > /dev/null 2>&1 || true
        fi
        exit 1
    fi

    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Starting fresh (session cap: ${MAX_SESSION}s)" >> "${LOG_DIR}/activity.log"

    HEARTBEAT_FILE="${LOG_DIR}/heartbeat.json"
    printf '{"last_heartbeat":"%s","status":"booting","current_task":"starting fresh session"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${HEARTBEAT_FILE}"

    set +e
    claude --dangerously-skip-permissions "${STARTUP_PROMPT}" \
        > "${LOG_DIR}/stdout.log" 2> "${LOG_DIR}/stderr.log"
    EXIT_CODE=$?
    set -e

    # --- Clasifică ieșirea ---
    if tail -20 "${LOG_DIR}/stderr.log" 2>/dev/null | grep -qi "rate.limit\|429\|capacity"; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) RATE_LIMITED" >> "${CRASH_LOG}"
        RATE_COUNT=$(grep -c "RATE_LIMITED" "${CRASH_LOG}" 2>/dev/null || echo "0")
        BACKOFF=$((300 * (RATE_COUNT > 3 ? 4 : RATE_COUNT + 1)))
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Backing off ${BACKOFF}s due to rate limiting" >> "${LOG_DIR}/activity.log"
        sleep ${BACKOFF}
        continue
    fi

    if [[ ${EXIT_CODE} -eq 0 ]]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Session ended cleanly, restarting fresh session" >> "${LOG_DIR}/activity.log"
        continue
    fi

    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) CRASH (exit ${EXIT_CODE})" >> "${CRASH_LOG}"
    echo "${TODAY}:$((CRASH_COUNT + 1))" > "${CRASH_COUNT_FILE}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Restarting in 5s after crash" >> "${LOG_DIR}/activity.log"
    sleep 5
done
