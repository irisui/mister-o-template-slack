# Memory Index

Last consolidated: 2026-08-22

## Topic Files

| File | Summary | Updated |
|------|---------|---------|
| [memory/facts.md](memory/facts.md) | Project state, system architecture, cron config | 2026-08-22 |

## Quick Reference

- Proiect fresh — fișierele bootstrap sunt template-uri necompletate
- 2 cron-uri: 1m Slack check, 30m heartbeat (config.json)
- Windows: Task Scheduler + Git Bash restart loop
- Canal Slack activ: `#asistent-nic`
- Memory type: `project-root`

---

<!--
MEMORY.md — Memorii pe termen lung

Fișierul de memorie persistentă al agentului.
Agentul actualizează acest fișier când învață ceva important.
Nu șterge niciodată intrările — doar adaugă sau amendează.
-->

## Starea proiectului

- [2026-08-22] Proiect `mister-o-template-slack` pornit — instalare fresh. Toate fișierele bootstrap (IDENTITY.md, SOUL.md, CONTRACT.md, USER.md, TOOLS.md, DECISIONS.md, GROUND-TRUTH.md) sunt încă template-uri goale, nepersonalizate. (source: sesiuni 2026-08-22, confidence: high)
- [2026-08-22] Agentul funcționează tehnic: pornire, cron-uri, Slack. Dar nu are identitate personalizată până când userul completează fișierele bootstrap.

## Preferințe și decizii

- [2026-08-22] Cron-uri configurate în config.json: 1m Slack check + 30m heartbeat. Recreate la fiecare session start. (source: config.json + sesiuni, confidence: high)
- [2026-08-22] Canalul Slack activ: `#asistent-nic`. Notificarea de online se trimite la fiecare pornire de sesiune.
- [2026-08-22] Platforma: Windows cu Task Scheduler + Git Bash restart loop (nu tmux/launchd). Scripturi în `scripts/agent-start-windows.sh` și `scripts/install-windows-autostart.ps1`.

## Fapte importante

- [2026-08-22] Prima zi de rulare a agentului. 3+ sesiuni pornite, toate cu pattern identic: bootstrap → crons → Slack online.
- [2026-08-22] Fișierul `.env` conține `SLACK_CHANNEL_ID` folosit de Slack bot scripts.

## Persoane

<!-- Persoane relevante cu care lucrezi sau despre care vorbești des -->
