#!/usr/bin/env python3
# PreToolUse hook -- alerteaza pe Slack la comenzi shell neobisnuit de
# periculoase, indiferent daca vin dintr-o decizie proprie a agentului sau
# dintr-un prompt-injection reusit (document/pagina/output care a convins
# agentul sa ruleze ceva ce nu i s-a cerut).
#
# Deliberat NU blocheaza executia (exit 0 mereu): un fals-pozitiv aici nu
# trebuie sa opreasca un task legitim al lui Nic. Rolul e alerta, nu polling
# activ de permisiuni -- CONTRACT.md/SOUL.md raman sursa de adevar pentru ce
# are voie agentul sa faca; asta e doar un semnal suplimentar catre Nic cand
# se intampla ceva neobisnuit, ca sa poata interveni daca ceva a scapat de
# sub control.
import json, sys, os, re, subprocess

PATTERNS = [
    (r"rm\s+-[a-z]*r[a-z]*f", "stergere recursiva fortata (rm -rf)"),
    (r"git\s+push\s+.*--force", "git push --force"),
    (r"git\s+push\s+.*-f\b", "git push -f"),
    (r"history\s+-c\b", "stergere istoric shell"),
    (r"\.env\b.*(curl|Invoke-WebRequest|wget)", "citire .env urmata de request extern"),
    (r"(curl|Invoke-WebRequest|wget).*(\.env\b)", "request extern cu .env implicat"),
    (r"(SLACK_BOT_TOKEN|ANTHROPIC_API_KEY|api[_-]?key)\s*=.*(curl|Invoke-WebRequest|wget)", "posibila exfiltrare de credentiale"),
    (r"reg\s+add\s+.*\\Run\b", "modificare cheie de auto-start Windows (Run)"),
    (r"schtasks\s+.*\/create", "creare task Windows Scheduler nou"),
    (r"Stop-Process.*-Force.*\*", "kill de procese cu wildcard"),
    (r"Remove-Item\s+.*-Recurse.*-Force", "stergere recursiva fortata (PowerShell)"),
]

def notify(level, msg):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    notify_bin = os.path.join(script_dir, "notify.sh")
    try:
        subprocess.run(["bash", notify_bin, level, msg], timeout=20,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass  # notify e best-effort, nu trebuie sa blocheze hook-ul

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    if tool_name not in ("Bash", "PowerShell"):
        sys.exit(0)

    tool_input = data.get("tool_input", {})
    command = tool_input.get("command", "") or ""
    if not command:
        sys.exit(0)

    for pattern, label in PATTERNS:
        if re.search(pattern, command, re.IGNORECASE):
            short_cmd = command.strip().replace("\n", " ")[:200]
            notify("warning", f"Comanda neobisnuit de riscanta detectata ({label}): {short_cmd}")
            break  # o singura alerta per comanda, chiar daca matcheaza mai multe tipare

    sys.exit(0)

if __name__ == "__main__":
    main()
