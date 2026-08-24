# Memory Index

Last consolidated: 2026-08-24

## Topic Files

| File | Summary | Updated |
|------|---------|---------|
| [memory/facts.md](memory/facts.md) | Project state, system architecture, cron config, bootstrap file status | 2026-08-24 |
| [memory/patterns.md](memory/patterns.md) | Session-restart behavior, cron re-creation, known fixed bugs (`.env` sourcing, crash false-positives) | 2026-08-24 |
| [memory/corrections.md](memory/corrections.md) | User's name is "Nic" not "Nick" | 2026-08-24 |

## Quick Reference

- Identitate: agent = "Nic", user = "Nic" (same first name, intentional — see [[corrections]]). IDENTITY.md, SOUL.md, CONTRACT.md, USER.md, TOOLS.md all filled in. Only DECISIONS.md și GROUND-TRUTH.md rămân template-uri goale.
- 2 cron-uri: 1m Slack check, 30m heartbeat (config.json) — **session-only**, trebuie rearmate la fiecare restart de sesiune (vezi [[patterns]])
- Windows: Task Scheduler + Git Bash restart loop (nu tmux/launchd) — restarturi frecvente sunt normale
- Canal Slack activ: `#asistent-nic` (ID `C0BRZEMMK6J`)
- `.env` sourcing bug în check-slack.sh/send-slack.sh — fixat 2026-08-23, verificat funcțional (vezi [[patterns]])
- Fals-pozitive de crash la auto-start (bootstrap-ul durează 2-5 min, verificarea vechea aștepta doar 10s) — fixat 2026-08-24 cu grace period de 5 min + retry pe `wt.exe`, testat end-to-end (vezi [[patterns]])
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
