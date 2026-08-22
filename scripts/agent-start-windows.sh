#!/usr/bin/env bash
# agent-start-windows.sh - Supraveghetor extern al agentului pe Windows.
#
# IMPORTANT: acest script NU ruleaza claude direct (asa cum facea prima
# versiune). Un `claude --dangerously-skip-permissions "PROMPT"` non-interactiv
# executa promptul si IESE dupa ce termina task-ul initial (setup crons +
# mesaj Slack) — nu ramane sa astepte cron-urile /loop create. Pe macOS,
# tmux tinea sesiunea "prinsa" intr-un PTY persistent indiferent de asta.
# Pe Windows, inlocuitorul de PTY persistent e o fereastra Windows Terminal
# cu claude interactiv (vezi install-windows-autostart.ps1, care lanseaza
# `wt.exe ... claude` direct).
#
# Rolul acestui script: supravegheaza acea fereastra din exterior. Daca
# procesul claude al agentului dispare (crash, utilizatorul a inchis
# fereastra), il relanseaza printr-o fereastra Windows Terminal noua.
# Nu ruleaza nimic in bucla stransa — verifica o data la CHECK_INTERVAL
# secunde, nu la fiecare cateva secunde ca varianta veche (evita bucla de
# "session ended cleanly, restart" observata cu abordarea non-interactiva).
#
# Usage: bash scripts/agent-start-windows.sh [project_dir]

set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_DIR="${HOME}/.agent-logs"
CRASH_LOG="${LOG_DIR}/crashes.log"
CRASH_COUNT_FILE="${LOG_DIR}/.crash_count_today"
MAX_CRASHES_PER_DAY=3
CHECK_INTERVAL=30          # secunde intre verificari ca procesul e viu
AGENT_MARKER="AGENT_SESSION_MARKER=mister-o-template-slack"  # vezi launch-agent-window.ps1

mkdir -p "${LOG_DIR}"

if [[ -f "${PROJECT_DIR}/.env" ]]; then
    set -a
    source "${PROJECT_DIR}/.env"
    set +a
fi

WT_LAUNCHER="${PROJECT_DIR}/scripts/launch-agent-window.ps1"
if [[ ! -f "${WT_LAUNCHER}" ]]; then
    echo "ERROR: nu gasesc ${WT_LAUNCHER}" >&2
    exit 1
fi

is_agent_running() {
    # Cauta un proces claude.exe pornit cu markerul acestui agent in linia de comanda.
    powershell.exe -NoProfile -Command \
        "if (Get-CimInstance Win32_Process -Filter \"Name='claude.exe'\" | Where-Object { \$_.CommandLine -like '*${AGENT_MARKER}*' }) { exit 0 } else { exit 1 }" \
        > /dev/null 2>&1
}

launch_agent_window() {
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Launching agent window" >> "${LOG_DIR}/activity.log"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${WT_LAUNCHER}" -ProjectDir "${PROJECT_DIR}" > /dev/null 2>&1 &
}

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) agent-start-windows.sh (supervisor mode) launched (project: ${PROJECT_DIR})" >> "${LOG_DIR}/activity.log"

launch_agent_window
sleep 10   # lasa fereastra sa porneasca inainte de primul check

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
            ALERT_TEXT="ALERT: Agentul a crapat de ${MAX_CRASHES_PER_DAY} ori azi si s-a oprit. Reporneste task-ul din Task Scheduler (my-agent-slack) cand esti gata."
            curl -s -X POST "https://slack.com/api/chat.postMessage" \
                -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
                -H "Content-type: application/json; charset=utf-8" \
                --data "$(jq -nc --arg ch "${SLACK_CHANNEL_ID}" --arg txt "${ALERT_TEXT}" '{channel: $ch, text: $txt}')" \
                > /dev/null 2>&1 || true
        fi
        exit 1
    fi

    sleep "${CHECK_INTERVAL}"

    if ! is_agent_running; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Agent window not found — treating as crash, relaunching" >> "${CRASH_LOG}"
        echo "${TODAY}:$((CRASH_COUNT + 1))" > "${CRASH_COUNT_FILE}"
        launch_agent_window
        sleep 10
    fi
done
