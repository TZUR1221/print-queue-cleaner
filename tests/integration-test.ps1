# integration-test.ps1 — בדיקת אמת מול Windows: יוצרת עבודת הדפסה תקועה אמיתית
# ובודקת שהמנוע מזהה ומוחק אותה. לא מדפיסה שום נייר:
# העבודה נוצרת ישר בתוך תור ההדפסה ומושהית לפני שהמדפסת מקבלת אותה.
#
# הרצה:  powershell -ExecutionPolicy Bypass -File tests\integration-test.ps1
# ברירת המחדל עובדת על "Microsoft Print to PDF" — מדפסת וירטואלית, בלי נייר ובלי דיו.
#   -Printer '<שם>'   כדי לבדוק על תור אחר

param(
    [string]$Printer = 'Microsoft Print to PDF',
    [switch]$KeepTempData
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root 'src'

. (Join-Path $src 'spooler-api.ps1')

$pass = 0; $fail = 0
function Check { param([string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { $script:pass++; Write-Host "  עובר   $Name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  נכשל   $Name  $Detail" -ForegroundColor Red }
}

Write-Host ''
Write-Host 'בדיקת אמת — עבודת הדפסה תקועה אמיתית' -ForegroundColor Cyan
Write-Host '-------------------------------------'

$all = @(Get-Printer | Select-Object -ExpandProperty Name)
if ($all -notcontains $Printer) {
    Write-Host "המדפסת '$Printer' אינה קיימת במחשב. המדפסות הקיימות:" -ForegroundColor Yellow
    $all | ForEach-Object { Write-Host "   $_" }
    exit 1
}

# תיקיית נתונים מבודדת, כדי שהבדיקה לא תיגע בהגדרות החיות
$tmpData = Join-Path $env:TEMP ('pqc-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmpData -Force | Out-Null
$testSettings = [ordered]@{
    enabled = $true; dryRun = $false
    printers = @($Printer)
    minutesNoProgress = 0; errorGraceMinutes = 0
    deleteOnError = $true; deletePaperOut = $true
    deletePaused = $true                       # בבדיקה כן, כי העבודה שיצרנו מושהית
    deletePrintedLeftovers = $true; printedLeftoverMinutes = 0
    spoolerResetEnabled = $false               # לא נוגעים בשירות ההדפסה בבדיקה
    spoolerResetAfterAttempts = 99; logKeepDays = 60
}
$testSettings | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $tmpData 'settings.json') -Encoding UTF8

$jobId = $null
try {
    $jobId = New-PQCPausedTestJob -PrinterName $Printer
    Write-Host "  נוצרה עבודת בדיקה בתור '$Printer' (מזהה $jobId)" -ForegroundColor Gray
    Start-Sleep -Milliseconds 700

    $job = Get-PrintJob -PrinterName $Printer -ID $jobId -ErrorAction SilentlyContinue
    Check 'Windows מדווח על העבודה בתור' ($null -ne $job)
    if ($job) {
        Write-Host "     מצב כפי ש-Windows מדווח: '$($job.JobStatus)'" -ForegroundColor Gray
        Write-Host "     שם המסמך: '$($job.DocumentName)'  |  עמודים: $($job.PagesPrinted)/$($job.TotalPages)" -ForegroundColor Gray
    }

    # סבב ראשון: מצב סימולציה — חייב לזהות אבל לא למחוק
    $out1 = & (Join-Path $src 'clear-queue.ps1') -DataDir $tmpData -DryRunOnly 2>&1 | Out-String
    $still = Get-PrintJob -PrinterName $Printer -ID $jobId -ErrorAction SilentlyContinue
    Check 'מצב סימולציה מזהה את העבודה' ($out1 -match 'סימולציה')
    Check 'מצב סימולציה לא מחק באמת' ($null -ne $still)

    # סבב שני: מחיקה אמיתית
    $out2 = & (Join-Path $src 'clear-queue.ps1') -DataDir $tmpData 2>&1 | Out-String
    Start-Sleep -Milliseconds 900
    $gone = Get-PrintJob -PrinterName $Printer -ID $jobId -ErrorAction SilentlyContinue
    Check 'העבודה התקועה נמחקה מהתור בפועל' ($null -eq $gone) "(הפלט: $($out2.Trim()))"

    # היומן נרשם בעברית קריאה
    $logFile = Get-ChildItem -Path (Join-Path $tmpData 'logs') -Filter '*.log' -ErrorAction SilentlyContinue |
               Select-Object -First 1
    $logOk = $false
    if ($logFile) {
        $txt = Get-Content -LiteralPath $logFile.FullName -Raw -Encoding UTF8
        $logOk = ($txt -match 'נמחקה עבודה תקועה')
    }
    Check 'היומן תיעד את המחיקה בעברית' $logOk

    # זיהוי המשימה המתוזמנת חייב לא לזהות כזב. גרסה קודמת בדקה מפתח
    # רישום ש-Test-Path מחזיר עליו True לכל שם, כולל מומצא — ואז הממשק
    # היה מכריז "מותקנת" גם כשלא. כאן מוודאים ששם מומצא מחזיר False.
    # הסדר חשוב: install-task טוען את common שמאפס את $PQCTaskName,
    # ולכן דורסים את השם רק אחרי הטעינה.
    . (Join-Path $src 'install-task.ps1') -Action status | Out-Null
    $PQCTaskName = 'PQC-NoSuchTask-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $fakeFound = Test-PQCTaskExistsLimited
    Check 'זיהוי המשימה לא מזהה כזב על שם מומצא' (-not $fakeFound)
    $PQCTaskName = 'PrintQueueCleaner'
}
finally {
    if ($jobId) {
        try { Remove-PQCPrintJob -PrinterName $Printer -JobId $jobId | Out-Null } catch {}
    }
    if (-not $KeepTempData) { Remove-Item -LiteralPath $tmpData -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "  נתוני הבדיקה נשמרו ב: $tmpData" -ForegroundColor Gray }
}

Write-Host '-------------------------------------'
Write-Host ("סה""כ: $pass עוברות, $fail נכשלות") -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host ''
if ($fail -gt 0) { exit 1 }
exit 0
