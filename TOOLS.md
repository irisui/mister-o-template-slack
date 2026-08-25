## Comunicare
- **Slack:** bot configurat via SLACK_BOT_TOKEN în .env
  - Poate trimite și primi mesaje în canalul privat `#asistent-nic` (SLACK_CHANNEL_ID)
  - Chat autorizat: SLACK_ALLOWED_USER în .env

## Fișiere și sistem
- Acces citire/scriere în directorul agentului (`mister-o-template-slack`)
- Windows nativ (fără WSL2) — bash via Git for Windows, fereastră Windows Terminal vizibilă pentru sesiunea interactivă
- Acces citire în directoarele documentate explicit de Nick

## Tooluri instalate
- Claude Code CLI
- Git for Windows (bash.exe)
- Windows Terminal (wt.exe)
- jq (via scoop) — necesar pentru scripturile Slack

## MCP servere active
- (niciunul configurat momentan — de completat dacă se adaugă)

## Securitate — hook-uri automate
- `scripts/scan-injection.sh` — scanează mesajele Slack și documentele descărcate după tipare de prompt-injection, alertează pe Slack (warning) dacă găsește ceva; rulat automat din `check-slack.sh`.
- `scripts/guard-dangerous.py` (hook `PreToolUse`) — alertează pe Slack la comenzi shell neobișnuit de riscante (ștergere recursivă forțată, `git push --force`, citire `.env` + request extern, exfiltrare de credențiale). Nu blochează execuția, doar alertează.
- `scripts/loop-detector.py` (hook `PreToolUse`, pre-existent) — blochează bucle infinite de apeluri identice de tool-uri.

## Nu am acces la
- Conturi sau servicii externe neconfigurate în .env
- Bani, plăți, abonamente
- Alte directoare/proiecte în afara celor documentate explicit
