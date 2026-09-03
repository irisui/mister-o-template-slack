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
- Prag de consolidare `dream`: 7 zile (168h), nu 24h — dar auto-trigger-ul (Stop hook) nu e instalat pe această mașină, deci pragul nu se verifică automat; toate consolidările de până acum au fost manuale, inclusiv 7 într-o singură zi pe 2026-09-03 (vezi [[patterns]] și [[facts]])
- Sesiuni paralele ale agentului pot face commit-uri concurente — verifică mereu `git status`/`git log` înainte de a presupune ce trebuie commis (vezi [[patterns]])
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
