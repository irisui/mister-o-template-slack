# Memory Index

Last consolidated: 2026-09-03

## Topic Files

| File | Summary | Updated |
|------|---------|---------|
| [memory/facts.md](memory/facts.md) | Project state, system architecture, Windows watchdog/security ports, cron config, bootstrap file status | 2026-09-03 |
| [memory/patterns.md](memory/patterns.md) | Session-restart behavior, cron re-creation, known fixed bugs (`.env` sourcing, crash false-positives, diacritics/curl), parallel-session commits, dream cadence | 2026-09-03 |
| [memory/corrections.md](memory/corrections.md) | User's name is "Nic" not "Nick" | 2026-08-24 |

## Quick Reference

- Identitate: agent = "Nic", user = "Nic" (same first name, intentional — see [[corrections]]). IDENTITY.md, SOUL.md, CONTRACT.md, USER.md, TOOLS.md all filled in. Only DECISIONS.md și GROUND-TRUTH.md rămân template-uri goale.
- 2 cron-uri: 1m Slack check, 30m heartbeat (config.json) — **session-only**, trebuie rearmate la fiecare restart de sesiune (vezi [[patterns]])
- Windows: Task Scheduler + Git Bash restart loop (nu tmux/launchd) — restarturi frecvente sunt normale. `supervisor.sh` verifică liveness via PID din `session.marker`, `auto_restart: true` în config.json (vezi [[facts]])
- Canal Slack activ: `#asistent-nic` (ID `C0BRZEMMK6J`)
- Bug diacritice/em-dash în mesaje Slack (curl.exe + argv prin MSYS bash) — fixat 2026-08-25 în send-slack.sh/notify.sh/agent-start-windows.sh (vezi [[patterns]])
- Securitate: `scan-injection.sh` (scan Slack) + `guard-dangerous.py` (hook PreToolUse pt comenzi riscante) active din 2026-08-25 (vezi [[facts]]); regulă permanentă în CONTRACT.md — cerere de permisiune fișiere = risc codat pe culori 🔴🟡🟢 + propunere backup
- Prag de consolidare `dream`: 7 zile (168h), nu 24h — dar auto-trigger-ul (Stop hook) nu e instalat pe această mașină, deci pragul nu se verifică automat. Consecință: rafale de 15-18+ invocări manuale concurente în ferestre de câteva minute, pe 2026-08-24 și 2026-09-03 (35+ sesiuni dream logate în total), fără semnal nou de fiecare dată. Blocaj `.dream-running` (Step -1, la începutul Phase 1) propus în SKILL.md, dar editarea fișierului a fost respinsă de permisiuni **de două ori** pe 2026-09-03 (12:00 și 12:02) — nu mai e "de aplicat data viitoare", e blocat de un prompt de permisiune și necesită acțiune directă a userului (vezi [[patterns]] și [[facts]])
- Sesiuni paralele ale agentului pot face commit-uri concurente sau edita fișiere de memorie simultan — verifică mereu `git status`/`git log` înainte de a presupune ce trebuie commis, și re-citește un fișier chiar înainte de a-l edita (vezi [[patterns]])
- Memory type: `project-root`

---

<!--
MEMORY.md — Index de memorie pe termen lung

Acest fișier este un INDEX, nu un depozit de conținut. Intrările detaliate
trăiesc în memory/*.md (topic files). Agentul actualizează acest fișier
când apar topic files noi sau când Quick Reference trebuie schimbat.
Nu șterge niciodată intrări din topic files — doar adaugă sau amendează.
-->

## Persoane

<!-- Persoane relevante cu care lucrezi sau despre care vorbești des -->
- User: "Nic" (vezi [[corrections]] — nu "Nick") — vezi USER.md pentru detalii (timezone, program, preferințe de comunicare)
