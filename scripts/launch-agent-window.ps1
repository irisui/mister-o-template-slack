# launch-agent-window.ps1 - Deschide o fereastra Windows Terminal cu Claude Code
# interactiv, echivalentul Windows al `tmux new-session -d ... claude ...`.
#
# De ce interactiv si nu `claude --dangerously-skip-permissions "PROMPT"` direct:
# rularea non-interactiva executa promptul si IESE dupa primul task (setup
# crons + mesaj Slack), nu ramane sa deserveasca cron-urile /loop create.
# O sesiune interactiva ramane deschisa, exact ca in tmux pe macOS.
#
# Fereastra ramane VIZIBILA (spre deosebire de varianta veche, complet ascunsa) —
# e limitarea acceptata pentru a avea o sesiune Claude Code reala, interactiva.
# Poate fi minimizata manual.
#
# AGENT_SESSION_MARKER e o variabila de mediu fara alt scop decat sa apara in
# linia de comanda a procesului claude.exe, ca scripts/agent-start-windows.sh
# sa poata detecta din exterior daca agentul mai ruleaza (via Win32_Process).
#
# Usage: powershell -File launch-agent-window.ps1 -ProjectDir "<path>"

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectDir
)

$ErrorActionPreference = "Stop"

$WtCandidates = @(
    "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
)
$WtExe = $WtCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $WtExe) {
    $cmd = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($cmd) { $WtExe = $cmd.Source }
}
if (-not $WtExe) {
    Write-Error "Windows Terminal (wt.exe) nu a fost gasit. Instaleaza-l: winget install Microsoft.WindowsTerminal"
    exit 1
}

$BashCandidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
)
$BashExe = $BashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $BashExe) {
    Write-Error "bash.exe (Git for Windows) nu a fost gasit."
    exit 1
}

# Prompt-ul de bootstrap — identic cu cel folosit pe macOS in agent-wrapper.sh.
# Trimis ca argument pozitional catre `claude` (nu -p/--print), exact ca pe
# macOS: fara -p, claude ramane interactiv dupa ce raspunde la promptul initial.
# Ceea ce lipsea in prima versiune Windows nu era asta, ci un TTY real — acolo
# stdout era redirectat spre fisiere log, ceea ce impinge claude spre
# comportament non-interactiv. O fereastra Windows Terminal ofera un TTY real,
# fara nicio redirectare, deci sesiunea ramane vie fara alt artificiu (SendKeys
# etc.) — comanda porneste deja cu promptul, nu trebuie tastat separat.
$StartupPrompt = "You are starting a new session. Read all bootstrap files listed in CLAUDE.md. Then read config.json and set up your crons using /loop for each entry in the crons array. Start with the comms cron (1m) first. After crons are set up, send a Slack message to the user saying you're back online and what you're about to work on."
$EscapedPrompt = $StartupPrompt.Replace("'", "'\''")

# Path complet catre shim-ul POSIX "claude" (fara extensie, instalat de npm
# langa claude.cmd) — cand bash.exe porneste dintr-un context Task Scheduler /
# PowerShell netriggerat de un shell login normal, PATH-ul poate sa nu includa
# folderul npm global si comanda esueaza cu "The system cannot find the file
# specified" (0x80070002), desi task-ul porneste corect fereastra.
# IMPORTANT: trebuie shim-ul POSIX ("claude"), NU claude.cmd — bash/MSYS nu
# poate exec direct un batch file Windows (.cmd) ca binar, indiferent de
# quoting; folosind path complet catre shim-ul fara extensie, bash il ruleaza
# ca orice alt script shell.
$ClaudeExeWin = "$env:APPDATA\npm\claude"
if (-not (Test-Path $ClaudeExeWin)) {
    Write-Error "claude (shim POSIX) nu a fost gasit la $ClaudeExeWin."
    exit 1
}
# Convertim path-ul Windows in format bash (C:\... -> /c/...) pentru comanda bash -lc.
$ClaudeExeBash = "/" + $ClaudeExeWin.Substring(0,1).ToLower() + $ClaudeExeWin.Substring(2).Replace('\','/')

# Scriem comanda intr-un fisier .sh temporar, in loc s-o dam ca string inline
# lui `wt.exe ... -- bash.exe -lc "..."`. Testat izolat: wt.exe isi face
# propriul split al argumentelor de dupa `--` inainte sa le paseze mai departe,
# si un string cu ';' si spatii/ghilimele imbricate (path-ul contine
# "Nick Popescu") se rupe la mijloc — wt.exe a incercat sa lanseze o bucata
# din prompt ca fisier separat ("read -p 'press enter''": file not found).
# Cu un singur fisier .sh ca argument, wt.exe nu mai are nimic de spart.
$AgentLogDir = Join-Path $env:USERPROFILE ".agent-logs"
New-Item -ItemType Directory -Force -Path $AgentLogDir | Out-Null
$LaunchScript = Join-Path $AgentLogDir "launch-agent.sh"

$ScriptContent = @"
export AGENT_SESSION_MARKER=mister-o-template-slack
cd '$ProjectDir'
'$ClaudeExeBash' --dangerously-skip-permissions '$EscapedPrompt'
"@
Set-Content -Path $LaunchScript -Value $ScriptContent -Encoding ASCII -NoNewline

$LaunchScriptBash = "/" + $LaunchScript.Substring(0,1).ToLower() + $LaunchScript.Substring(2).Replace('\','/')

# NOTA: "--title" cu o valoare ce contine spatiu ("Agent Slack") s-a dovedit
# a rupe parsing-ul argumentelor la wt.exe in acest mediu — titlul rezultat
# era doar "Agent", iar restul ("Slack -- bash.exe ...") era interpretat ca
# un program separat de lansat, cauzand exact eroarea 0x80070002 investigata
# aici. Titlu fara spatiu ("AgentSlack") evita problema.
#
# NOTA 2: acelasi wt.exe rupe la spatiu si argumentul cu path-ul scriptului
# ($LaunchScriptBash contine "Nick Popescu"), daca nu e ghilimeluit explicit —
# altfel bash.exe primeste "/c/Users/Nick" si "Popescu/..." ca doua argumente
# separate ("No such file or directory"). Ghilimele explicite in string.
Start-Process -FilePath $WtExe -ArgumentList @(
    "new-tab",
    "--title", "AgentSlack",
    "--",
    $BashExe, "`"$LaunchScriptBash`""
)
