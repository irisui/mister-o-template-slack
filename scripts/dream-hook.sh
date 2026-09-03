#!/usr/bin/env bash
# Dream hook pentru Mister O.
# Verifica daca trebuie consolidare memorie (7 zile), daca da lanseaza dream ca subagent background.
#
# NU mai e legat automat de Stop hook (scos din .claude/settings.json pe 2026-09-03,
# la cererea userului: "vreau sa decid eu cand se executa Dream"). Ruleaza doar
# manual/on-demand, ex. cerut explicit agentului sau rulat direct:
#   bash scripts/dream-hook.sh
#
# Protectie anti-suprapunere (fix 2026-09-03, dupa 39 de rulari paralele intr-o
# fereastra de 23 min care au dus la depasirea limitei de tokeni/sesiune):
# - lock file cu PID, verificat viu inainte de a considera o rulare anterioara "in curs"
# - lock stale (proces mort) e curatat automat, ca sa nu blocheze Dream la nesfarsit
# - .last-dream e actualizat IMEDIAT la pornire, nu doar la final, ca Stop-urile
#   care se declanseaza in timp ce Dream ruleaza inca (loop la 1 minut) sa vada
#   deja timestamp-ul proaspat si sa nu mai reporneasca alta instanta

AGENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_DIR="$AGENT_DIR/.claude/skills/dream"
LOCK_FILE="$AGENT_DIR/.dream.lock"
LAST_DREAM_FILE="$AGENT_DIR/.last-dream"

# Daca exista deja un lock cu un proces inca viu, nu mai pornim alta rulare
if [[ -f "$LOCK_FILE" ]]; then
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$LOCK_PID" ]] && kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "Dream deja in curs (PID $LOCK_PID) - se sare peste"
        exit 0
    fi
    # Lock stale (procesul nu mai exista) - curatat
    rm -f "$LOCK_FILE"
fi

if bash "$SKILL_DIR/should-dream.sh" 2>/dev/null; then
    # Marcam pornirea INAINTE de a lansa procesul, ca Stop-urile urmatoare
    # (posibil la cateva secunde distanta, din loop-ul de 1 minut) sa vada deja
    # conditia "prea devreme" si sa nu mai duplice rularea.
    date +%s > "$LAST_DREAM_FILE"

    nohup claude -p \
        "Run the Dream memory consolidation skill. Read '${SKILL_DIR}/SKILL.md' and execute all 4 phases for the project at '${AGENT_DIR}'. Memory type: project-root. Memory path: '${AGENT_DIR}'." \
        --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
        > "/tmp/agent-dream-$(date +%Y%m%d-%H%M%S).log" 2>&1 &

    DREAM_PID=$!
    echo "$DREAM_PID" > "$LOCK_FILE"
    echo "Dream consolidation pornit in background (PID: $DREAM_PID)"

    # Curatare lock cand procesul background chiar se termina (fara sa blocheze hook-ul)
    ( wait "$DREAM_PID" 2>/dev/null; rm -f "$LOCK_FILE" ) &
    disown
fi

exit 0
