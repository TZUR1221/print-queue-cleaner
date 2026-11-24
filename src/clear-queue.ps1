# clear-queue.ps1 — הרצה אחת: סורק את תורי ההדפסה, מוחק את מה שתקוע, רושם ביומן.
# זה הקובץ שהמשימה המתוזמנת מפעילה כל 2 דקות.
#   -Quiet       בלי פלט למסך (ברירת המחדל של המשימה המתוזמנת)
#   -DryRunOnly  כופה מצב סימולציה גם אם ההגדרות אומרות אחרת

param(
    [switch]$Quiet,
    [switch]$DryRunOnly,
    [string]$DataDir
)

$ErrorActionPreference = 'Stop'
if ($DataDir) { $PQCDataDirOverride = $DataDir }
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'engine.ps1')
. (Join-Path $PSScriptRoot 'spooler-api.ps1')

# Write-Output ולא Write-Host: הפלט חייב לזרום בצינור כדי שהממשק
# יוכל להציג אותו בתיבת "בדוק עכשיו"
function Write-Out {
    param([string]$Text)
    if (-not $Quiet) { Write-Output $Text }
}

function Get-PQCTargetPrinters {
    param($Settings)
    $all = @()
    try {
        $all = @(Get-Printer -ErrorAction Stop | Select-Object -ExpandProperty Name)
    } catch {
        Write-PQCLog "לא ניתן לקרוא את רשימת המדפסות: $($_.Exception.Message)" 'שגיאה'
        return @()
    }
    $wanted = @($Settings.printers | Where-Object { $_ })
    if ($wanted.Count -eq 0) { return $all }           # ריק = כל המדפסות
    $hit  = @($all | Where-Object { $wanted -contains $_ })
    $miss = @($wanted | Where-Object { $all -notcontains $_ })
    foreach ($m in $miss) { Write-PQCLog "המדפסת '$m' מופיעה בהגדרות אך אינה קיימת במחשב — מדולגת" 'אזהרה' }
    $hit
}

function Reset-PQCSpooler {
    # מוצא אחרון: עבודה שמסרבת להימחק משוחררת רק בעצירת שירות ההדפסה
    # ומחיקת קובצי התור מהדיסק.
    $spoolDir = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'
    Write-PQCLog 'מאפס את שירות ההדפסה (Spooler)' 'פעולה'
    Stop-Service -Name Spooler -Force -ErrorAction Stop
    $removed = 0
    if (Test-Path -LiteralPath $spoolDir) {
        Get-ChildItem -LiteralPath $spoolDir -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.SHD', '.SPL', '.shd', '.spl') } |
            ForEach-Object {
                try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $removed++ } catch {}
            }
    }
    Start-Service -Name Spooler -ErrorAction Stop
    Write-PQCLog "שירות ההדפסה הופעל מחדש. נמחקו $removed קובצי תור מהדיסק." 'פעולה'
    $removed
}

# ---------- הרצה ----------

$now      = Get-Date
$settings = Get-PQCSettings
if ($DryRunOnly) { $settings.dryRun = $true }

$status = [ordered]@{
    time         = $now.ToString('o')
    enabled      = [bool]$settings.enabled
    dryRun       = [bool]$settings.dryRun
    printers     = @()
    scanned      = 0
    deleted      = 0
    failed       = 0
    spoolerReset = $false
    elevated     = (Test-PQCElevated)
    note         = ''
}

if (-not $settings.enabled) {
    $status.note = 'מושבת בהגדרות'
    Save-PQCRunStatus $status
    Write-Out 'המערכת מושבתת בהגדרות — לא בוצעה פעולה.'
    return
}

$printers = Get-PQCTargetPrinters $settings
$status.printers = $printers

$jobs = @()
foreach ($p in $printers) {
    try {
        $jobs += @(Get-PrintJob -PrinterName $p -ErrorAction Stop)
    } catch {
        # תור ריק אינו שגיאה; מדפסת שלא נגישה כן — ונרשמת פעם אחת
        $msg = $_.Exception.Message
        if ($msg -notmatch 'no print job|לא נמצא') {
            Write-PQCLog "קריאת התור של '$p' נכשלה: $msg" 'אזהרה'
        }
    }
}
$status.scanned = $jobs.Count

if ($jobs.Count -eq 0) {
    Save-PQCState @{}
    Save-PQCRunStatus $status
    Remove-PQCOldLogs -KeepDays $settings.logKeepDays
    Write-Out 'התור ריק בכל המדפסות שבטיפול.'
    return
}

$prevState = Get-PQCState
$result    = Get-PQCQueueDecisions -Jobs $jobs -State $prevState -Now $now -Settings $settings
$newState  = $result.state

$toDelete  = @($result.decisions | Where-Object { $_.action -eq 'delete' })
$failedKeys = @()

foreach ($d in $toDelete) {
    $label = "'$($d.document)' (מדפסת: $($d.printer), מזהה: $($d.id), משתמש: $($d.user))"
    if ($settings.dryRun) {
        Write-PQCLog "[סימולציה] הייתי מוחק $label — $($d.reason)" 'סימולציה'
        Write-Out "[סימולציה] $label — $($d.reason)"
        continue
    }
    $res = Remove-PQCPrintJob -PrinterName $d.printer -JobId $d.id
    if ($res.ok) {
        Write-PQCLog "נמחקה עבודה תקועה: $label — $($d.reason) [$($res.method)]" 'מחיקה'
        Write-Out "נמחקה: $label"
        $status.deleted++
        $newState.Remove($d.key)
    } else {
        $failedKeys += $d.key
        $status.failed++
        $tries = [int]$newState[$d.key].attempts + 1
        $newState[$d.key].attempts = $tries
        Write-PQCLog "מחיקה נכשלה (ניסיון $tries): $label — $($res.error)" 'אזהרה'
        Write-Out "מחיקה נכשלה: $label"
    }
}

# עבודה עקשנית: אחרי כמה נסיונות כושלים מאפסים את שירות ההדפסה,
# אבל רק אם אין באותו רגע עבודה אחרת שמדפיסה בפועל.
$stubborn = @($failedKeys | Where-Object { [int]$newState[$_].attempts -ge [int]$settings.spoolerResetAfterAttempts })
if ($stubborn.Count -gt 0) {
    if (-not $settings.spoolerResetEnabled) {
        Write-PQCLog "יש $($stubborn.Count) עבודות שמסרבות להימחק, ואיפוס שירות ההדפסה כבוי בהגדרות. נדרשת התערבות." 'אזהרה'
    } elseif (-not (Test-PQCElevated)) {
        Write-PQCLog 'נדרש איפוס שירות ההדפסה אך ההרצה אינה בהרשאות מנהל.' 'אזהרה'
    } elseif (-not (Test-PQCSpoolerResetAllowed -Decisions $result.decisions -FailedKeys $failedKeys)) {
        Write-PQCLog 'נדרש איפוס שירות ההדפסה, אך יש כרגע עבודה אחרת שמדפיסה בפועל — נדחה להרצה הבאה.' 'אזהרה'
    } else {
        try {
            Reset-PQCSpooler | Out-Null
            $status.spoolerReset = $true
            foreach ($k in $stubborn) { $newState.Remove($k) }
        } catch {
            Write-PQCLog "איפוס שירות ההדפסה נכשל: $($_.Exception.Message)" 'שגיאה'
        }
    }
}

Save-PQCState $newState
Save-PQCRunStatus $status
Remove-PQCOldLogs -KeepDays $settings.logKeepDays

$kept = @($result.decisions | Where-Object { $_.action -eq 'keep' }).Count
Write-Out "סריקה הושלמה: $($jobs.Count) עבודות בתור, נמחקו $($status.deleted), נותרו $kept."
if ($status.deleted -gt 0 -or $status.failed -gt 0 -or $settings.dryRun) {
    # שורת סיכום ביומן רק כשקרה משהו, כדי שהיומן לא יתפח מסריקות שקטות
    Write-PQCLog "סיכום סריקה: בתור $($jobs.Count), נמחקו $($status.deleted), כשלו $($status.failed)." 'סיכום'
}
