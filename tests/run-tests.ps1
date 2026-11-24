# run-tests.ps1 — בדיקות למנוע ההחלטה. לא נוגעות במדפסות אמיתיות:
# בונות עבודות מדומות, מריצות את ההחלטה, ומשוות למה שאמור לקרות.
# הרצה:  powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1

$ErrorActionPreference = 'Stop'
$src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
. (Join-Path $src 'engine.ps1')

$pass = 0; $fail = 0
$now  = Get-Date '2026-11-24T10:00:00'

function Get-TestSettings {
    [ordered]@{
        enabled = $true; dryRun = $false; printers = @()
        minutesNoProgress = 5; errorGraceMinutes = 1
        deleteOnError = $true; deletePaperOut = $false; deletePaused = $false
        deletePrintedLeftovers = $true; printedLeftoverMinutes = 10
        spoolerResetEnabled = $true; spoolerResetAfterAttempts = 3; logKeepDays = 60
    }
}

function New-TestJob {
    param(
        [string]$Printer = 'תת שחור לבן',
        [int]$Id = 1,
        [string]$Status = 'Printing',
        [string]$Doc = 'מבחן בחומש.pdf',
        [int]$Pages = 0,
        [double]$Size = 1000,
        [datetime]$Submitted = $now,
        [int]$TotalPages = 10
    )
    [pscustomobject]@{
        PrinterName = $Printer; Id = $Id; JobStatus = $Status; DocumentName = $Doc
        PagesPrinted = $Pages; Size = $Size; SubmittedTime = $Submitted
        TotalPages = $TotalPages; UserName = 'מורה'
    }
}

# מצב מההרצה הקודמת, כאילו ראינו את העבודה לפני X דקות
function New-PrevState {
    param($Job, [int]$MinutesAgoSeen = 10, [int]$MinutesAgoProgress = 10, [int]$Pages = 0, [double]$Size = 1000, [int]$Attempts = 0)
    $k = Get-PQCJobKey $Job
    @{ $k = [ordered]@{
        firstSeen      = $now.AddMinutes(-1 * $MinutesAgoSeen).ToString('o')
        lastProgressAt = $now.AddMinutes(-1 * $MinutesAgoProgress).ToString('o')
        pages          = $Pages
        size           = $Size
        status         = $Job.JobStatus
        attempts       = $Attempts
        printer        = $Job.PrinterName
        document       = $Job.DocumentName
    } }
}

function Assert-Action {
    param([string]$Name, $Job, $State, [string]$Expected, $Settings = $null)
    if (-not $Settings) { $Settings = Get-TestSettings }
    $r = Get-PQCQueueDecisions -Jobs @($Job) -State $State -Now $now -Settings $Settings
    $actual = $r.decisions[0].action
    if ($actual -eq $Expected) {
        $script:pass++
        Write-Host ("  עובר   " + $Name) -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host ("  נכשל   " + $Name + "  — צפוי '$Expected', קיבלנו '$actual' (סיבה: $($r.decisions[0].reason))") -ForegroundColor Red
    }
}

Write-Host ''
Write-Host 'בדיקות מנוע איפוס תור ההדפסות' -ForegroundColor Cyan
Write-Host '--------------------------------'

# 1. עבודה שנראית בפעם הראשונה — אף פעם לא נמחקת מיד, גם אם נשלחה מזמן
$j = New-TestJob -Status 'Printing' -Submitted $now.AddHours(-3)
Assert-Action 'עבודה חדשה לנו, אפילו ישנה — לא נמחקת בסריקה הראשונה' $j @{} 'keep'

# 2. עבודה שמדפיסה ומתקדמת — נשארת
$j = New-TestJob -Status 'Printing' -Pages 42
$st = New-PrevState -Job $j -MinutesAgoSeen 30 -MinutesAgoProgress 30 -Pages 17
Assert-Action 'עבודה ארוכה שמתקדמת (17 עמודים ואז 42) — נשארת' $j $st 'keep'

# 3. עבודה שעומדת 10 דקות בלי להתקדם — נמחקת
$j = New-TestJob -Status 'Printing' -Pages 3
$st = New-PrevState -Job $j -MinutesAgoProgress 10 -Pages 3
Assert-Action 'עבודה שלא זזה 10 דקות — נמחקת' $j $st 'delete'

# 4. עבודה שעומדת 3 דקות בלבד — עדיין נשארת (הסף 5)
$j = New-TestJob -Status 'Printing' -Pages 3
$st = New-PrevState -Job $j -MinutesAgoProgress 3 -Pages 3
Assert-Action 'עבודה שלא זזה 3 דקות (סף 5) — נשארת' $j $st 'keep'

# 5. שגיאה אחרי זמן החסד — נמחקת
$j = New-TestJob -Status 'Error' -Submitted $now.AddMinutes(-5)
$st = New-PrevState -Job $j -MinutesAgoSeen 5 -MinutesAgoProgress 5
Assert-Action 'עבודה בשגיאה 5 דקות — נמחקת' $j $st 'delete'

# 6. שגיאה בת 20 שניות — בזמן חסד, נשארת
$j = New-TestJob -Status 'Error' -Submitted $now.AddSeconds(-20)
$st = New-PrevState -Job $j -MinutesAgoSeen 0.33 -MinutesAgoProgress 0.33
Assert-Action 'עבודה בשגיאה 20 שניות — בזמן חסד, נשארת' $j $st 'keep'

# 7. מדפסת לא מחוברת
$j = New-TestJob -Status 'Offline'
$st = New-PrevState -Job $j -MinutesAgoSeen 4 -MinutesAgoProgress 4
Assert-Action 'מדפסת לא מחוברת (Offline) — נמחקת' $j $st 'delete'

# 8. כיבוי מחיקת שגיאות בהגדרות
$s = Get-TestSettings; $s.deleteOnError = $false
$j = New-TestJob -Status 'Error'
$st = New-PrevState -Job $j -MinutesAgoSeen 60 -MinutesAgoProgress 60
Assert-Action 'שגיאה כשהמחיקה כבויה בהגדרות — נשארת' $j $st 'keep' $s

# 9. חסר נייר — ברירת מחדל לא נוגעים
$j = New-TestJob -Status 'PaperOut'
$st = New-PrevState -Job $j -MinutesAgoSeen 60 -MinutesAgoProgress 60
Assert-Action 'ממתינה לנייר — כברירת מחדל נשארת' $j $st 'keep'

# 10. חסר נייר כשהמתג דלוק
$s = Get-TestSettings; $s.deletePaperOut = $true
Assert-Action 'ממתינה לנייר כשהמתג דלוק — נמחקת' $j $st 'delete' $s

# 11. מושהית בכוונה — לא נוגעים
$j = New-TestJob -Status 'Paused'
$st = New-PrevState -Job $j -MinutesAgoSeen 60 -MinutesAgoProgress 60
Assert-Action 'עבודה מושהית — כברירת מחדל נשארת' $j $st 'keep'

# 12. תקועה במחיקה — המקרה שחוסם את כל התור
$j = New-TestJob -Status 'Deleting'
$st = New-PrevState -Job $j -MinutesAgoSeen 4 -MinutesAgoProgress 4
Assert-Action 'תקועה במחיקה 4 דקות — נמחקת שוב' $j $st 'delete'

# 13. הודפסה ונשארה בתור מעל 10 דקות
$j = New-TestJob -Status 'Printed, Retained' -Pages 10
$st = New-PrevState -Job $j -MinutesAgoSeen 20 -MinutesAgoProgress 20 -Pages 10
Assert-Action 'הודפסה ונשארה בתור 20 דקות — מנוקה' $j $st 'delete'

# 14. "Retained" אבל עוד מדפיסה — לא נוגעים
$j = New-TestJob -Status 'Printing, Retained' -Pages 55
$st = New-PrevState -Job $j -MinutesAgoSeen 40 -MinutesAgoProgress 40 -Pages 20
Assert-Action 'שמורה אך עדיין מדפיסה ומתקדמת — נשארת' $j $st 'keep'

# 15. איפוס ספולר אסור כשעבודה אחרת מדפיסה בפועל
$stuck  = New-TestJob -Id 7 -Status 'Deleting'
$moving = New-TestJob -Id 8 -Status 'Printing' -Pages 30 -Printer 'גנים שחור'
$st = New-PrevState -Job $moving -MinutesAgoSeen 5 -MinutesAgoProgress 5 -Pages 10
$r  = Get-PQCQueueDecisions -Jobs @($stuck, $moving) -State $st -Now $now -Settings (Get-TestSettings)
$allowed = Test-PQCSpoolerResetAllowed -Decisions $r.decisions -FailedKeys @((Get-PQCJobKey $stuck))
if (-not $allowed) { $pass++; Write-Host '  עובר   איפוס ספולר נחסם כשיש הדפסה פעילה אחרת' -ForegroundColor Green }
else { $fail++; Write-Host '  נכשל   איפוס ספולר היה צריך להיחסם' -ForegroundColor Red }

# 16. איפוס ספולר מותר כשאין שום דבר שזז
$st = New-PrevState -Job $stuck -MinutesAgoSeen 10 -MinutesAgoProgress 10
$r  = Get-PQCQueueDecisions -Jobs @($stuck) -State $st -Now $now -Settings (Get-TestSettings)
$allowed = Test-PQCSpoolerResetAllowed -Decisions $r.decisions -FailedKeys @((Get-PQCJobKey $stuck))
if ($allowed) { $pass++; Write-Host '  עובר   איפוס ספולר מותר כשאין הדפסה פעילה' -ForegroundColor Green }
else { $fail++; Write-Host '  נכשל   איפוס ספולר היה צריך להיות מותר' -ForegroundColor Red }

# 17. המצב החדש זוכר את זמן ההתקדמות כשהעבודה זזה
$j = New-TestJob -Status 'Printing' -Pages 99
$st = New-PrevState -Job $j -MinutesAgoProgress 20 -Pages 50
$r = Get-PQCQueueDecisions -Jobs @($j) -State $st -Now $now -Settings (Get-TestSettings)
$k = Get-PQCJobKey $j
if (([datetime]$r.state[$k].lastProgressAt) -eq $now) {
    $pass++; Write-Host '  עובר   שעון ההתקדמות מתאפס כשנדפס עוד עמוד' -ForegroundColor Green
} else {
    $fail++; Write-Host '  נכשל   שעון ההתקדמות לא התאפס' -ForegroundColor Red
}

# 18. עבודות שנעלמו מהתור נעלמות גם מהמצב (לא מצטבר לנצח)
$old = New-TestJob -Id 55 -Status 'Printing'
$st  = New-PrevState -Job $old
$r   = Get-PQCQueueDecisions -Jobs @() -State $st -Now $now -Settings (Get-TestSettings)
if ($r.state.Keys.Count -eq 0) {
    $pass++; Write-Host '  עובר   מצב של עבודה שנעלמה מהתור נמחק' -ForegroundColor Green
} else {
    $fail++; Write-Host '  נכשל   נותר זבל במצב' -ForegroundColor Red
}

Write-Host '--------------------------------'
Write-Host ("סה""כ: $pass עוברות, $fail נכשלות") -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host ''
if ($fail -gt 0) { exit 1 }
exit 0
