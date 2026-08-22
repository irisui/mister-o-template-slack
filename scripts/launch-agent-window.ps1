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

$BashCommand = "export AGENT_SESSION_MARKER=mister-o-template-slack; cd '$ProjectDir'; claude --dangerously-skip-permissions '$EscapedPrompt'"

Start-Process -FilePath $WtExe -ArgumentList @(
    "new-tab",
    "--title", "Agent Slack",
    "--",
    $BashExe, "-lc", $BashCommand
)
