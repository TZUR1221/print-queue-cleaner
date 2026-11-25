# install-task.ps1 — התקנה / הסרה / בדיקה של ההרצה האוטומטית כל 2 דקות
# המשימה רצה תחת חשבון SYSTEM, כדי שתעבוד גם כשאף אחד לא מחובר למחשב
# וכדי שתהיה לה הרשאה למחוק עבודות של כל המשתמשים.
#   .\install-task.ps1 install
#   .\install-task.ps1 remove
#   .\install-task.ps1 status

param(
    [ValidateSet('install', 'remove', 'status')]
    [string]$Action = 'status',
    [int]$IntervalMinutes = 2
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$scriptPath = Join-Path $PSScriptRoot 'clear-queue.ps1'
$psArgs     = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Quiet' -f $scriptPath

function Get-PQCTask {
    Get-ScheduledTask -TaskName $PQCTaskName -ErrorAction SilentlyContinue
}

# בלי הרשאות מנהל אי אפשר לקרוא משימה שרצה תחת SYSTEM, אבל אפשר בכל זאת
# לדעת אם היא קיימת: ממשק ה-COM של מתזמן המשימות מחזיר שתי שגיאות שונות —
#   0x80070005 "אין הרשאה"  => המשימה קיימת, רק חסומה לקריאה
#   0x80070002 "לא נמצא"    => המשימה באמת אינה קיימת
# (אומת 24/11/2026. אין להשתמש כאן ב-Test-Path על מפתח הרישום של
#  TaskCache\Tree — הוא מחזיר True לכל שם, גם מומצא.)
function Test-PQCTaskExistsLimited {
    $svc = $null
    try {
        $svc = New-Object -ComObject Schedule.Service
        $svc.Connect()
        $null = $svc.GetFolder('\').GetTask($PQCTaskName)
        return $true
    } catch {
        $ex = $_.Exception
        while ($ex.InnerException) { $ex = $ex.InnerException }
        $hr = 0
        try { $hr = [int]$ex.HResult } catch {}
        return ($hr -eq -2147024891)   # 0x80070005
    } finally {
        if ($svc) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($svc) }
    }
}

# שתי הגרסאות — זו וגרסת ה-exe — חולקות את שם המשימה PrintQueueCleaner.
# אם ה-exe כבר מותקן, התקנה מכאן הייתה מחליפה אותו בשקט ומשאירה את
# ההגדרות והיומן שלו מאחור. לכן עוצרים ומסבירים.
function Assert-PQCNotExeInstallation {
    try {
        $t = Get-ScheduledTask -TaskName $PQCTaskName -ErrorAction SilentlyContinue
        if (-not $t) { return }
        foreach ($a in $t.Actions) {
            # schtasks שומר את הנתיב עם מרכאות כשיש בו רווחים, ולכן
            # Execute חוזר כ-"C:\...\x.exe" ולא כ-C:\...\x.exe.
            # בלי החיתוך הזה כל התאמה שמסתיימת ב-exe$ נכשלת בשקט.
            $exe = ([string]$a.Execute).Trim().Trim('"').Trim()
            if ($exe -and $exe -match '\.exe$' -and $exe -notmatch '(^|\\)powershell\.exe$') {
                throw ("על המחשב הזה מותקנת גרסת ה-exe של המערכת:`n  $exe`n`n" +
                       "התקנה מכאן הייתה מחליפה אותה ומשאירה את ההגדרות והיומן שלה מאחור. " +
                       "כדי לנהל את המערכת, יש לפתוח את ה-exe הזה. " +
                       "כדי לחזור דווקא לגרסת הסקריפטים — להסיר קודם את ההרצה האוטומטית מתוך ה-exe.")
            }
        }
    } catch [System.Management.Automation.RuntimeException] { throw }
    catch { }   # לא הצלחנו לקרוא את המשימה — לא חוסמים בגלל זה
}

function Install-PQCTask {
    if (-not (Test-PQCElevated)) { throw 'התקנת המשימה דורשת הרשאות מנהל.' }
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw "לא נמצא הקובץ $scriptPath" }
    Assert-PQCNotExeInstallation

    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs
    $trg = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(1)
    # חזרה אין-סופית כל X דקות: בונים את תבנית החזרה ישירות,
    # כי New-ScheduledTaskTrigger לבדו לא תמיד מייצר "ללא תאריך סיום".
    $rep = New-CimInstance -ClassName MSFT_TaskRepetitionPattern `
                           -Namespace 'Root/Microsoft/Windows/TaskScheduler' `
                           -Property @{ Interval = ('PT{0}M' -f $IntervalMinutes); StopAtDurationEnd = $false } `
                           -ClientOnly
    $trg.Repetition = $rep

    $prn = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $set = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
                                        -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
                                        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                                        -StartWhenAvailable

    try {
        Register-ScheduledTask -TaskName $PQCTaskName -Action $act -Trigger $trg `
                               -Principal $prn -Settings $set `
                               -Description ('איפוס תור הדפסות — מוחק עבודות תקועות כל {0} דקות. פרויקט: {1}' -f $IntervalMinutes, $PQCRoot) `
                               -Force | Out-Null
        Write-PQCLog "ההרצה האוטומטית הותקנה (כל $IntervalMinutes דקות, חשבון SYSTEM)." 'פעולה'
    } catch {
        # מסלול גיבוי: schtasks עובד גם כשמודול ה-CIM מתעצבן
        Write-PQCLog "Register-ScheduledTask נכשל ($($_.Exception.Message)) — מנסה דרך schtasks." 'אזהרה'
        $tr = 'powershell.exe {0}' -f $psArgs
        & schtasks.exe /create /tn $PQCTaskName /tr $tr /sc minute /mo $IntervalMinutes /ru SYSTEM /rl HIGHEST /f | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "גם schtasks נכשל (קוד $LASTEXITCODE)." }
        Write-PQCLog "ההרצה האוטומטית הותקנה דרך schtasks (כל $IntervalMinutes דקות)." 'פעולה'
    }
    Get-PQCTaskStatus
}

function Uninstall-PQCTask {
    if (-not (Test-PQCElevated)) { throw 'הסרת המשימה דורשת הרשאות מנהל.' }
    if (Get-PQCTask) {
        Unregister-ScheduledTask -TaskName $PQCTaskName -Confirm:$false
        Write-PQCLog 'ההרצה האוטומטית הוסרה.' 'פעולה'
    }
    Get-PQCTaskStatus
}

# זהירות: בלי הרשאות מנהל, Get-ScheduledTask על משימה שרצה תחת SYSTEM
# מחזיר "לא נמצא" ו-Get-ScheduledTaskInfo זורק Access denied — גם כשהמשימה
# מותקנת ורצה (אומת 24/11/2026). לכן יש נפילה חזרה למפתח הרישום של מתזמן
# המשימות, שנקרא גם למשתמש רגיל. בלעדיו הממשק היה מכריז "לא מותקנת" בשקר.
function Get-PQCTaskStatus {
    $t = Get-PQCTask
    if (-not $t) {
        if (Test-PQCTaskExistsLimited) {
            return [pscustomobject]@{
                installed = $true; state = 'מותקנת'; lastRun = $null; nextRun = $null
                lastResult = $null; interval = $null; limited = $true
            }
        }
        return [pscustomobject]@{ installed = $false; state = 'לא מותקנת'; lastRun = $null; nextRun = $null; lastResult = $null; interval = $null; limited = $false }
    }
    $info = Get-ScheduledTaskInfo -TaskName $PQCTaskName -ErrorAction SilentlyContinue
    $interval = $null
    try {
        $iv = $t.Triggers[0].Repetition.Interval
        if ($iv -match 'PT(\d+)M') { $interval = [int]$Matches[1] }
    } catch {}
    [pscustomobject]@{
        installed  = $true
        state      = [string]$t.State
        lastRun    = $info.LastRunTime
        nextRun    = $info.NextRunTime
        lastResult = $info.LastTaskResult
        interval   = $interval
        limited    = $false
    }
}

switch ($Action) {
    'install' { Install-PQCTask }
    'remove'  { Uninstall-PQCTask }
    'status'  { Get-PQCTaskStatus }
}
