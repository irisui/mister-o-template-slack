#!/usr/bin/env bash
# Independent watchdog, varianta Windows. Ruleaza o data per tick (apelat de
# Task Scheduler la interval, sau intr-o bucla din agent-start-windows.sh),
# apoi iese. Deliberat NU foloseste 'set -e': o eroare interna nu trebuie sa
# se propage intr-un fel care ar putea afecta agentul. Logam si iesim 0.
#
# Echivalentul Windows al supervisor.sh original (macOS/tmux/launchctl):
# - tmux has-session               -> proces claude.exe viu, identificat prin
#                                      fisierul marker scris de launch-agent-window.ps1
#                                      (vezi acolo: launch-agent-window.ps1
#                                      scrie PID-ul via 'exec' inainte de a
#                                      porni claude, deci PID-ul din marker
#                                      devine PID-ul lui claude.exe insusi)
# - launchctl kickstart            -> launch-agent-window.ps1 (fereastra noua
#                                      Windows Terminal cu claude interactiv)
# - stat -f %z (BSD)               -> stat -c %s (GNU, din Git for Windows)
#
# Decizia HEALTHY/GRACE/DOWN si flap-detection/backoff/pathological raman
# neschimbate — logica pura vine din lib/supervisor-lib.sh, neschimbata.
set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${LIB_DIR}/.." && pwd)}"
# shellcheck disable=SC1091
source "${LIB_DIR}/lib/supervisor-lib.sh"

CONFIG_FILE="${CONFIG_FILE:-${PROJECT_DIR}/config.json}"
ENV_FILE="${ENV_FILE:-${PROJECT_DIR}/.env}"
STATE_DIR="${STATE_DIR:-${HOME}/.agent-logs}"
LOG_FILE="${LOG_FILE:-${STATE_DIR}/supervisor.log}"
ALIVE_FILE="${ALIVE_FILE:-${STATE_DIR}/alive}"
MARKER_FILE="${MARKER_FILE:-${STATE_DIR}/session.marker}"
NOTIFY_BIN="${NOTIFY_BIN:-${LIB_DIR}/notify.sh}"
LAUNCH_WINDOW_PS1="${LAUNCH_WINDOW_PS1:-${LIB_DIR}/launch-agent-window.ps1}"
LOG_MAX_BYTES=1048576

mkdir -p "$STATE_DIR"
LAST_TICK_F="${STATE_DIR}/.supervisor_last_tick"
RESTARTS_F="${STATE_DIR}/.supervisor_restarts"
GRACE_F="${STATE_DIR}/.supervisor_grace_until"
LAST_ALERT_F="${STATE_DIR}/.supervisor_last_alert"
SESS_F="${STATE_DIR}/.supervisor_sess_created"

now="${NOW_EPOCH:-$(date -u +%s)}"

cfg() { jq -r ".supervisor.$1 // empty" "$CONFIG_FILE" 2>/dev/null || true; }
TICK="$(cfg tick_seconds)";            TICK="${TICK:-240}"
STALE="$(cfg liveness_stale_seconds)"; STALE="${STALE:-2700}"
FC="$(cfg flap_count)";                FC="${FC:-3}"
FW="$(cfg flap_window_seconds)";       FW="${FW:-1800}"
PC="$(cfg pathological_count)";        PC="${PC:-6}"
PW="$(cfg pathological_window_seconds)"; PW="${PW:-7200}"
DRY="$(cfg dry_run)";                  DRY="${DRY:-false}"
AR="$(cfg auto_restart)";             AR="${AR:-false}"
BACKOFF_CSV="$(jq -r '(.supervisor.backoff_schedule // [600,1200,1800]) | map(tostring) | join(",")' "$CONFIG_FILE" 2>/dev/null || echo "600,1200,1800")"

rotate_if_needed() {
  [[ -f "$LOG_FILE" ]] || return 0
  local size; size="$(stat -c %s "$LOG_FILE" 2>/dev/null || stat -f %z "$LOG_FILE" 2>/dev/null || echo 0)"
  if [[ "$(should_rotate "$size" "$LOG_MAX_BYTES")" == "1" ]]; then
    mv -f "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
  fi
}
log() { rotate_if_needed; printf '%s %s\n' "$(date -u -d "@$now" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$now")" "$*" >> "$LOG_FILE"; }

read_int() { local f="$1" d="$2"; if [[ -f "$f" ]]; then cat "$f"; else echo "$d"; fi; }

# Proces claude.exe cu PID-ul din marker inca viu? (echivalentul Windows al
# 'tmux has-session'). Foloseste 'ps -p' din Git for Windows (functioneaza pe
# PID-uri Windows), nu Get-Process, ca sa evitam un fork powershell.exe la
# fiecare tick.
agent_process_present() {
  [[ -f "$MARKER_FILE" ]] || return 1
  local pid; pid="$(cat "$MARKER_FILE" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  ps -p "$pid" >/dev/null 2>&1
}

launch_agent_window() {
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${LAUNCH_WINDOW_PS1}" -ProjectDir "${PROJECT_DIR}" > /dev/null 2>&1
}

main() {
  local last_tick alive grace_until agent_present slept state marker_mtime prev_marker_mtime
  last_tick="$(read_int "$LAST_TICK_F" 0)"
  alive="$(read_int "$ALIVE_FILE" 0)"
  grace_until="$(read_int "$GRACE_F" 0)"

  if agent_process_present; then agent_present=1; else agent_present=0; fi

  # Cold-start grace: un marker NOU (mtime diferit de ultima verificare)
  # inseamna ca agentul tocmai a (re)pornit si n-a apucat inca sa scrie primul
  # heartbeat beacon. Acordam o fereastra de gratie ca un agent sanatos,
  # proaspat pornit, sa nu fie clasificat DOWN pe baza unui beacon vechi. Un
  # blocaj real pastreaza acelasi marker si tot e prins; marker absent tot
  # inseamna DOWN.
  marker_mtime=""
  if [[ "$agent_present" -eq 1 && -f "$MARKER_FILE" ]]; then
    marker_mtime="$(stat -c %Y "$MARKER_FILE" 2>/dev/null || stat -f %m "$MARKER_FILE" 2>/dev/null || true)"
  fi
  prev_marker_mtime="$(read_int "$SESS_F" "")"
  if [[ "$agent_present" -eq 1 && -n "$marker_mtime" && "$marker_mtime" != "$prev_marker_mtime" ]]; then
    grace_until=$(( now + STALE ))
    echo "$grace_until" > "$GRACE_F"
    echo "$marker_mtime" > "$SESS_F"
    log "STARTUP detected (marker mtime ${marker_mtime}) grace_until=${grace_until}"
  fi

  slept="$(compute_slept "$now" "$last_tick" "$TICK")"
  if [[ "$slept" == "1" ]]; then
    grace_until=$(( now + STALE ))
    echo "$grace_until" > "$GRACE_F"
    log "SLEEP detected (gap $(( now - last_tick ))s) grace_until=${grace_until}"
  fi

  state="$(classify_state "$agent_present" "$alive" "$now" "$STALE" "$grace_until")"

  case "$state" in
    HEALTHY|GRACE)
      log "${state} agent_present=${agent_present} alive_age=$(( now - alive ))s"
      ;;
    DOWN)
      local restarts decision
      restarts="$(read_int "$RESTARTS_F" "")"
      decision="$(flap_decision "$restarts" "$now" "$FC" "$FW" "$PC" "$PW" "$BACKOFF_CSV")"
      if [[ "$DRY" == "true" ]]; then
        log "DRY DOWN -> would act decision=${decision} agent_present=${agent_present} alive_age=$(( now - alive ))s"
      else
        case "$decision" in
          OK)
            if [[ "$AR" == "true" ]]; then
              launch_agent_window
              restarts="${restarts:+${restarts},}${now}"
              echo "$restarts" > "$RESTARTS_F"
              log "DOWN -> RESTART (launch-agent-window.ps1) restarts=[${restarts}]"
              "$NOTIFY_BIN" info "Agentul Nic era jos, l-am repornit la $(date -u -d "@$now" +%H:%MZ 2>/dev/null || echo "$now"). Sunt iar online." || true
            else
              local last_alert; last_alert="$(read_int "$LAST_ALERT_F" 0)"
              log "DOWN -> ALERT-ONLY (auto_restart off) no restart"
              if [[ $(( now - last_alert )) -ge "$STALE" ]]; then
                echo "$now" > "$LAST_ALERT_F"
                "$NOTIFY_BIN" warning "Agentul Nic e jos. auto_restart e oprit, nu repornesc automat. Reporneste manual (Task Scheduler: my-agent-slack, sau bash scripts/agent-start-windows.sh)." || true
              fi
            fi
            ;;
          BACKOFF:*)
            local secs="${decision#BACKOFF:}" last_alert
            last_alert="$(read_int "$LAST_ALERT_F" 0)"
            log "DOWN -> BACKOFF ${secs}s (flapping) no restart"
            if [[ $(( now - last_alert )) -ge "$secs" ]]; then
              echo "$now" > "$LAST_ALERT_F"
              "$NOTIFY_BIN" warning "Agentul Nic se tot reporneste, intru in backoff ${secs}s." || true
            fi
            ;;
          PATHOLOGICAL)
            local last_alert; last_alert="$(read_int "$LAST_ALERT_F" 0)"
            log "DOWN -> PATHOLOGICAL auto-restart oprit"
            if [[ $(( now - last_alert )) -ge "$PW" ]]; then
              echo "$now" > "$LAST_ALERT_F"
              local tail_err; tail_err="$(tail -3 "${STATE_DIR}/stderr.log" 2>/dev/null | tr '\n' ' ' | cut -c1-300)"
              "$NOTIFY_BIN" red "Agentul Nic e jos si nu se stabilizeaza singur. Ai nevoie sa intervii. Ultima eroare: ${tail_err}" || true
            fi
            ;;
        esac
      fi
      ;;
  esac

  echo "$now" > "$LAST_TICK_F"
}

# Defensive wrapper: orice eroare e logata, niciodata propagata.
if ! main 2>>"${LOG_FILE}"; then
  log "ERROR supervisor main failed (handled, exiting 0)"
fi
exit 0
