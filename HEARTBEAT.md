# Heartbeat Checklist

Acest fișier este citit la fiecare heartbeat (implicit: la 30 de minute).
Adaugă task-uri pe care vrei ca agentul să le execute periodic.

## Task-uri de bază (activ mereu)

- [ ] Rulează `bash scripts/mark-alive.sh` (semnal de liveness pentru supervisor)
- [ ] Verifică dacă există mesaje Slack noi (dacă nu a rulat cron-ul de 1m)
- [ ] Actualizează fișierul de memorie zilnică cu ce s-a întâmplat
- [ ] Trimite raport zilnic de stare pe Slack dacă e ora 22:00 sau mai târziu și nu a fost deja trimis azi (activitate, erori, stare sisteme) — vezi `scripts/daily-report.sh`

## Task-uri opționale (decomentează sau adaugă)

<!-- - [ ] Verifică starea serviciilor din GROUND-TRUTH.md -->
<!-- - [ ] Rulează un script de monitorizare -->

---

*Adaugă orice task recurent pe care vrei să-l automatizezi.*
