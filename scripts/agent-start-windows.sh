#!/usr/bin/env bash
# agent-start-windows.sh - Punct de intrare pentru Task Scheduler pe Windows.
#
# Porneste agentul (fereastra Windows Terminal cu claude interactiv, vezi
# launch-agent-window.ps1) si apoi ruleaza supervisor.sh in bucla, o data la
# fiecare tick_seconds (din config.json -> supervisor.tick_seconds).
#
# De ce nu ruleaza claude direct: un `claude --dangerously-skip-permissions
# "PROMPT"` non-interactiv executa promptul si IESE dupa ce termina task-ul
# initial (setup crons + mesaj Slack) — nu ramane sa astepte cron-urile /loop
# create. Pe Windows, inlocuitorul de sesiune persistenta e o fereastra
# Windows Terminal cu claude interactiv.
#
# Toata logica de detectie DOWN/flapping/backoff/alertare traieste in
# supervisor.sh (impreuna cu lib/supervisor-lib.sh, functii pure si testate
# in supervisor-selftest.sh) — acest script e doar bucla care il invoca la
# interval si porneste initial fereastra.
#
# Usage: bash scripts/agent-start-windows.sh [project_dir]
set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_DIR="${HOME}/.agent-logs"
CONFIG_FILE="${PROJECT_DIR}/config.json"

mkdir -p "${LOG_DIR}"

if [[ -f "${PROJECT_DIR}/.env" ]]; then
    set -a
    source "${PROJECT_DIR}/.env"
    set +a
fi

WT_LAUNCHER="${PROJECT_DIR}/scripts/launch-agent-window.ps1"
SUPERVISOR="${PROJECT_DIR}/scripts/supervisor.sh"
if [[ ! -f "${WT_LAUNCHER}" ]]; then
    echo "ERROR: nu gasesc ${WT_LAUNCHER}" >&2
    exit 1
fi
if [[ ! -f "${SUPERVISOR}" ]]; then
    echo "ERROR: nu gasesc ${SUPERVISOR}" >&2
    exit 1
fi

TICK_SECONDS="$(jq -r '.supervisor.tick_seconds // 240' "${CONFIG_FILE}" 2>/dev/null || echo 240)"

launch_agent_window() {
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Launching agent window" >> "${LOG_DIR}/activity.log"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${WT_LAUNCHER}" -ProjectDir "${PROJECT_DIR}" > /dev/null 2>&1 &
}

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) agent-start-windows.sh launched (project: ${PROJECT_DIR}, tick=${TICK_SECONDS}s)" >> "${LOG_DIR}/activity.log"

launch_agent_window

while true; do
    sleep "${TICK_SECONDS}"
    PROJECT_DIR="${PROJECT_DIR}" bash "${SUPERVISOR}" || true
done
