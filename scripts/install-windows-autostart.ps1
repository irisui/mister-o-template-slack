# install-windows-autostart.ps1 - Inregistreaza agentul in Windows Task Scheduler.
#
# Echivalentul Windows pentru generate-launchd.sh de pe macOS: creeaza un task
# care porneste agentul automat la fiecare logon al userului curent, ruland
# in fundal (fereastra ascunsa) printr-o sesiune Git Bash care executa
# scripts/agent-start-windows.sh (bucla de auto-restart la crash).
#
# Cerinte: Git for Windows instalat (git-bash.exe in PATH sau locatie standard),
# Claude Code CLI instalat si autentificat (`claude` in PATH).
#
# Usage (din PowerShell, in folderul proiectului sau oriunde):
#   .\scripts\install-windows-autostart.ps1
#
# Dezinstalare:
#   Unregister-ScheduledTask -TaskName "my-agent-slack" -Confirm:$false

param(
    [string]$ProjectDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$TaskName = "my-agent-slack"

# Gaseste bash.exe (Git for Windows)
$BashCandidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
$BashExe = $BashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $BashExe) {
    $cmd = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($cmd) { $BashExe = $cmd.Source }
}

if (-not $BashExe) {
    Write-Error "Nu am gasit bash.exe (Git for Windows). Instaleaza Git for Windows: https://git-scm.com/download/win"
    exit 1
}

$ScriptPath = Join-Path $ProjectDir "scripts\agent-start-windows.sh"
if (-not (Test-Path $ScriptPath)) {
    Write-Error "Nu am gasit $ScriptPath"
    exit 1
}

Write-Output "Bash gasit la: $BashExe"
Write-Output "Proiect: $ProjectDir"

# Sterge task-ul vechi daca exista (reinstall idempotent)
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

# Actiunea: ruleaza bash.exe cu scriptul, fara fereastra vizibila
$WrappedPath = $ScriptPath -replace '\\', '/' -replace '^([A-Za-z]):', '/$1'
$WrappedPath = $WrappedPath.Substring(0,1) + $WrappedPath.Substring(1,1).ToLower() + $WrappedPath.Substring(2)

$Action = New-ScheduledTaskAction `
    -Execute $BashExe `
    -Argument "-lc `"bash '$ScriptPath'`"" `
    -WorkingDirectory $ProjectDir

# Trigger: la logon-ul userului curent
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# Setari: ruleaza doar cat userul e logat, fara fereastra, restart daca esueaza
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -Hidden `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0)  # fara limita de timp

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Description "Porneste agentul personal Claude Code + Slack la logon (mister-o-template-slack)" `
    -RunLevel Limited `
    | Out-Null

Write-Output ""
Write-Output "Task '$TaskName' inregistrat. Agentul va porni automat la urmatorul logon."
Write-Output ""
Write-Output "Comenzi utile:"
Write-Output "  Porneste acum (fara sa astepti logon):  Start-ScheduledTask -TaskName '$TaskName'"
Write-Output "  Verifica starea:                        Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo"
Write-Output "  Opreste task-ul programat:               Disable-ScheduledTask -TaskName '$TaskName'"
Write-Output "  Dezinstaleaza complet:                   Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
Write-Output ""
Write-Output "Loguri agent: $env:USERPROFILE\.agent-logs\activity.log"
