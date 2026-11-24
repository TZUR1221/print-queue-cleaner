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

function Install-PQCTask {
    if (-not (Test-PQCElevated)) { throw 'התקנת המשימה דורשת הרשאות מנהל.' }
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw "לא נמצא הקובץ $scriptPath" }

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

function Get-PQCTaskStatus {
    $t = Get-PQCTask
    if (-not $t) {
        return [pscustomobject]@{ installed = $false; state = 'לא מותקנת'; lastRun = $null; nextRun = $null; lastResult = $null; interval = $null }
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
    }
}

switch ($Action) {
    'install' { Install-PQCTask }
    'remove'  { Uninstall-PQCTask }
    'status'  { Get-PQCTaskStatus }
}
