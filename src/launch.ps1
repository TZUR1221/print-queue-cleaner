# launch.ps1 — מה שקורה בלחיצה על "הפעלה.bat".
# שני דברים: מסיר את סימון "נחסם" שקבצים מקבלים כשהם נפרסים מקובץ ZIP
# שהועבר ממחשב אחר, ואז פותח את חלון ההגדרות בהרשאות מנהל.

$ErrorActionPreference = 'SilentlyContinue'

$root = Split-Path -Parent $PSScriptRoot
Get-ChildItem -LiteralPath $root -Recurse -File -Include *.ps1, *.bat |
    Unblock-File

$ui = Join-Path $PSScriptRoot 'settings-ui.ps1'
if (-not (Test-Path -LiteralPath $ui)) {
    Write-Host "לא נמצא הקובץ $ui" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}

$id    = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$admin = (New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole(
             [System.Security.Principal.WindowsBuiltInRole]::Administrator)

if ($admin) {
    & $ui
} else {
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $ui)
}
