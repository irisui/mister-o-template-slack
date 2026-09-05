# TODO — Nic

Lista de task-uri și deadline-uri, ținută manual. Folosită de Agentul Nic pentru recap zilnic.

Format: `- [ ]` task deschis, `- [x]` task făcut. Deadline opțional în paranteză, format `(YYYY-MM-DD)`.

## Azi

- [ ]

## Săptămâna asta

- [ ]

## Fără deadline / cândva

- [ ]

## Făcute recent
<!-- Agentul poate muta aici task-urile bifate la recap, ca lista de sus să rămână curată -->

---

## Spec: Triaj Gmail zilnic (stabilit cu Nic 2026-09-05, de implementat)

- **Program:** cron nou, zilnic la **21:00** (ora locală Nic, Europe/Bucharest).
- **Domeniu:** doar emailuri **necitite din ultimele 24h** (`is:unread newer_than:1d`
  sau echivalent) — NU reprocesa stocul vechi de necitite din inbox.
- **Criteriu urgent/poate aștepta:** fără reguli fixe de cuvinte-cheie sau listă de
  expeditori — Claude citește subiect + expeditor + început conținut și judecă
  liber, caz cu caz.
- **Acțiune asupra Gmail-ului:** strict read-only. Nu muta, nu marca, nu șterge,
  nu adăuga labels.
- **Output:** un mesaj în `#asistent-nic`, format scurt:
  ```
  📬 Triaj Gmail (ultimele 24h) — N necitite noi
  🔴 Urgent (x): [expeditor] subiect — motiv scurt
  🟢 Poate aștepta (y): rezumat pe scurt / grupare pe tip
  ```
  Dacă 0 necitite noi în 24h → mesaj scurt "nimic nou", nu tăcere.
- **De decis chiar de tine (agentule) la implementare, propune-i lui Nic:**
  - Cum gestionezi un volum mare într-o zi (50+ emailuri) — rezumi pe grupuri? trunchiezi?
