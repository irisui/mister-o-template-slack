#!/usr/bin/env bash
# daily-report.sh - Trimite raportul zilnic de stare pe Slack, o singura data pe zi.
#
# Rulat din HEARTBEAT.md (heartbeat la 30 min): daca ora curenta e >= REPORT_HOUR
# si raportul de azi nu a fost deja trimis, aduna activitate/erori/stare din
# log-uri si trimite un mesaj pe Slack prin notify.sh (info level).
#
# Usage: bash scripts/daily-report.sh
set -uo pipefail

REPORT_HOUR=22   # ora dupa care se trimite raportul (24h format, local time)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${HOME}/.agent-logs"
STATE_FILE="${LOG_DIR}/.last-daily-report"
ACTIVITY_LOG="${LOG_DIR}/activity.log"
CRASH_LOG="${LOG_DIR}/crashes.log"

mkdir -p "${LOG_DIR}"

TODAY="$(date +%Y-%m-%d)"
CURRENT_HOUR="$(date +%H)"
# forta baza 10, altfel "08"/"09" sunt interpretate octal si dau eroare
CURRENT_HOUR=$((10#$CURRENT_HOUR))

# Nu inca ora de raport
if (( CURRENT_HOUR < REPORT_HOUR )); then
    exit 0
fi

# Deja trimis azi
if [[ -f "${STATE_FILE}" ]] && [[ "$(cat "${STATE_FILE}")" == "${TODAY}" ]]; then
    exit 0
fi

# --- Aduna datele raportului ---

# Cate crash-uri fals-pozitive / halt-uri azi (din crashes.log)
CRASH_COUNT=0
HALT_COUNT=0
if [[ -f "${CRASH_LOG}" ]]; then
    CRASH_COUNT=$(grep -c "^${TODAY}.*treating as crash" "${CRASH_LOG}" 2>/dev/null || echo 0)
    HALT_COUNT=$(grep -c "^${TODAY}.*HALTED" "${CRASH_LOG}" 2>/dev/null || echo 0)
fi

# Cate (re)lansari azi (din activity.log)
LAUNCH_COUNT=0
if [[ -f "${ACTIVITY_LOG}" ]]; then
    LAUNCH_COUNT=$(grep -c "^${TODAY}.*Launching agent window" "${ACTIVITY_LOG}" 2>/dev/null || echo 0)
fi

# Stare curenta: agentul e "viu" daca alive-file a fost atins in ultima ora
ALIVE_STATUS="necunoscuta"
if [[ -f "${LOG_DIR}/alive" ]]; then
    ALIVE_TS=$(cat "${LOG_DIR}/alive" 2>/dev/null || echo 0)
    NOW_TS=$(date +%s)
    if (( NOW_TS - ALIVE_TS < 3600 )); then
        ALIVE_STATUS="online"
    else
        ALIVE_STATUS="posibil oprit (ultimul semnal cu peste 1h in urma)"
    fi
fi

REPORT="Raport zilnic ${TODAY}
Stare: ${ALIVE_STATUS}
Relansari azi: ${LAUNCH_COUNT}
Crash-uri fals-pozitive azi: ${CRASH_COUNT}
Halt-uri (supervisor oprit) azi: ${HALT_COUNT}"

# --- Trimite pe Slack (nu esueaza hard daca notify.sh nu are credentiale) ---
bash "${SCRIPT_DIR}/notify.sh" info "${REPORT}"

# Marcheaza raportul de azi ca trimis, indiferent daca notify.sh a reusit efectiv
# (evita retrimitere in bucla la fiecare heartbeat cand credentialele lipsesc)
echo "${TODAY}" > "${STATE_FILE}"
