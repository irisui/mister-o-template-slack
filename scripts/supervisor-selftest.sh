#!/usr/bin/env bash
# End-to-end supervisor simulation (varianta Windows) with shortened timings
# and a fake launcher. Proves the mechanism without waiting for real wedges.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUP="${ROOT}/scripts/supervisor.sh"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
state="${work}/state"; mkdir -p "$state"
log="${state}/supervisor.log"
marker="${state}/session.marker"
envf="${work}/.env"; printf 'SLACK_BOT_TOKEN="T"\nSLACK_CHANNEL_ID="9"\n' > "$envf"
cfg="${work}/config.json"
cat > "$cfg" <<'EOF'
{"supervisor":{"tick_seconds":10,"liveness_stale_seconds":60,"flap_count":3,"flap_window_seconds":120,"backoff_schedule":[5,10,15],"pathological_count":6,"pathological_window_seconds":600,"dry_run":false,"auto_restart":true}}
EOF
lc="${work}/lc"; nf="${work}/nf"

# Fake "powershell.exe": emuleaza doar 'powershell.exe ... -File <script> ...',
# rulandu-l cu bash — asa supervisor.sh poate apela launch_agent_window() ca
# in productie (via powershell.exe -File launch-agent-window.ps1) fara sa aiba
# nevoie de un .ps1 real in test.
psbin="${work}/powershell.exe"
cat > "$psbin" <<'PSEOF'
#!/usr/bin/env bash
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "-File" ]]; then
    j=$((i+1))
    bash "${!j}"
    exit $?
  fi
done
exit 1
PSEOF
chmod +x "$psbin"

# Fake "launch-agent-window.ps1": inregistreaza apelul si scrie un marker nou
# (simuleaza ce face scriptul real — porneste o sesiune noua, scrie PID-ul ei).
launcher="${work}/launch-agent-window.ps1"
cat > "$launcher" <<EOF
#!/usr/bin/env bash
echo "launch" >> "${lc}"
echo "\$\$" > "${marker}"
EOF
chmod +x "$launcher"

cat > "${work}/notify" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "${nf}"
EOF
chmod +x "${work}/notify"

run() { # now agent_present
  if [[ "$2" == "1" ]]; then
    [[ -f "$marker" ]] || echo "$$" > "$marker"
  else
    echo "999999999" > "$marker"
  fi
  PATH="${work}:${PATH}" \
  CONFIG_FILE="$cfg" ENV_FILE="$envf" STATE_DIR="$state" LOG_FILE="$log" \
  MARKER_FILE="$marker" LAUNCH_WINDOW_PS1="$launcher" NOTIFY_BIN="${work}/notify" \
  NOW_EPOCH="$1" bash "$SUP"
}
fail() { echo "SELFTEST RED: $1"; exit 1; }

# Simuleaza o sesiune deja cunoscuta de supervisor de la un tick anterior:
# scrie direct .supervisor_sess_created cu mtime-ul curent al marker-ului
# (fara sa ruleze efectiv supervisor.sh), ca urmatorul run() sa NU mai
# detecteze STARTUP si sa NU acorde GRACE nejustificat.
establish_known_session() {
  echo "$$" > "$marker"
  local mtime; mtime="$(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker" 2>/dev/null)"
  echo "$mtime" > "${state}/.supervisor_sess_created"
  rm -f "${state}/.supervisor_grace_until"
}

reset_session_tracking() {
  rm -f "${state}/.supervisor_sess_created" "${state}/.supervisor_grace_until" "$marker"
}

# 1. Healthy: fresh beacon, agent present, sesiune deja cunoscuta -> no restart.
reset_session_tracking
establish_known_session
echo "1000" > "${state}/alive"; echo "995" > "${state}/.supervisor_last_tick"
run 1005 1
[[ -f "$lc" ]] && fail "healthy caused a restart"

# 2. Wedge: beacon frozen, agent present (aceeasi sesiune), awake -> restart + info.
reset_session_tracking
establish_known_session
echo "1000" > "${state}/alive"; echo "1100" > "${state}/.supervisor_last_tick"
run 1105 1
grep -q launch "$lc" || fail "wedge did not restart"
grep -q info "$nf" || fail "wedge did not notify info"

# 3. Crash: agent gone -> restart.
reset_session_tracking
establish_known_session
: > "$lc"
echo "2000" > "${state}/alive"; echo "1995" > "${state}/.supervisor_last_tick"
run 2005 0
grep -q launch "$lc" || fail "crash did not restart"

# 4. Sleep tolerance: huge tick gap -> GRACE, no restart even though beacon stale.
reset_session_tracking
establish_known_session
: > "$lc"
echo "1000" > "${state}/alive"; echo "1000" > "${state}/.supervisor_last_tick"
run 9000 1
[[ -f "$lc" && -s "$lc" ]] && fail "slept tick caused a restart"
grep -q GRACE "$log" || fail "sleep not classified as GRACE"

# 5. Flapping: many recent restarts -> BACKOFF, no restart, warning.
reset_session_tracking
establish_known_session
: > "$lc"; : > "$nf"
echo "1000" > "${state}/alive"; echo "9995" > "${state}/.supervisor_last_tick"
echo "9960,9970,9980" > "${state}/.supervisor_restarts"
run 10000 1
[[ -s "$lc" ]] && fail "flapping caused a restart"
grep -q warning "$nf" || fail "flapping did not warn"

# 6. Cold start: NEW agent session (marker rescris = mtime nou), beacon stale,
# agent present -> GRACE, no restart.
reset_session_tracking
: > "$lc"; : > "$nf"
rm -f "${state}/.supervisor_restarts"
echo "1000" > "${state}/alive"; echo "12995" > "${state}/.supervisor_last_tick"
run 13000 1
[[ -s "$lc" ]] && fail "cold-start caused a restart"
grep -q "STARTUP detected" "$log" || fail "cold-start not detected"

# 7. Alert-only (auto_restart=false): wedge -> notify, NO restart.
sed 's/"auto_restart":true/"auto_restart":false/' "$cfg" > "${cfg}.ar0"; cfg="${cfg}.ar0"
reset_session_tracking
establish_known_session
: > "$lc"; : > "$nf"; rm -f "${state}/.supervisor_restarts"
echo "1000" > "${state}/alive"; echo "13995" > "${state}/.supervisor_last_tick"
run 14000 1
[[ -s "$lc" ]] && fail "alert-only caused a restart"
grep -q warning "$nf" || fail "alert-only did not warn"
grep -q "ALERT-ONLY" "$log" || fail "alert-only not logged"

# 8. dry_run: wedge but no action.
cfg="${work}/config.json"
sed 's/"dry_run":false/"dry_run":true/' "$cfg" > "${cfg}.dry"; cfg="${cfg}.dry"
reset_session_tracking
establish_known_session
: > "$lc"; : > "$nf"; rm -f "${state}/.supervisor_restarts"
echo "1000" > "${state}/alive"; echo "11995" > "${state}/.supervisor_last_tick"
run 12000 1
[[ -s "$lc" ]] && fail "dry_run caused a restart"
[[ -s "$nf" ]] && fail "dry_run caused a notify"
grep -q DRY "$log" || fail "dry_run not logged"

echo "SELFTEST GREEN"
