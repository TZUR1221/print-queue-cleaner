# engine.ps1 — ההחלטה מי "תקוע": קוד טהור בלי קריאות למדפסות, כדי שאפשר לבדוק אותו
# מקבל רשימת עבודות (אובייקטים עם השדות של Get-PrintJob), את המצב מההרצה הקודמת
# ומחזיר רשימת החלטות + מצב חדש.

function Get-PQCJobKey($Job) {
    $ticks = 0
    if ($Job.SubmittedTime) { $ticks = ([datetime]$Job.SubmittedTime).Ticks }
    '{0}|{1}|{2}' -f $Job.PrinterName, $Job.Id, $ticks
}

function Test-PQCStatus {
    param($Status, [string[]]$Needles)
    $s = [string]$Status
    foreach ($n in $Needles) { if ($s -match $n) { return $true } }
    $false
}

function Get-PQCQueueDecisions {
    param(
        [object[]]$Jobs,
        $State,
        [datetime]$Now,
        $Settings
    )

    if ($null -eq $State) { $State = @{} }
    $newState  = @{}
    $decisions = @()

    foreach ($job in @($Jobs)) {
        $key    = Get-PQCJobKey $job
        $status = [string]$job.JobStatus
        $pages  = 0; if ($null -ne $job.PagesPrinted) { $pages = [int]$job.PagesPrinted }
        $size   = 0; if ($null -ne $job.Size)         { $size  = [double]$job.Size }

        $submitted = $Now
        if ($job.SubmittedTime) { $submitted = [datetime]$job.SubmittedTime }

        $prev       = $null
        if ($State -is [hashtable]) { $prev = $State[$key] } else { $prev = $State.$key }

        $attempts   = 0
        $progressed = $true
        if ($prev) {
            $firstSeen      = [datetime]$prev.firstSeen
            $lastProgressAt = [datetime]$prev.lastProgressAt
            $attempts       = [int]$prev.attempts
            $progressed     = ($pages -ne [int]$prev.pages) -or ($size -ne [double]$prev.size)
            if ($progressed) { $lastProgressAt = $Now }
        } else {
            # בפעם הראשונה שאנחנו רואים עבודה אין לנו דרך לדעת אם היא מתקדמת.
            # firstSeen לפי זמן השליחה (לצורך חישוב שגיאות), אבל שעון ההתקדמות
            # מתחיל עכשיו — כדי לא להרוג עבודה ארוכה שבאמת מדפיסה.
            $firstSeen      = $submitted
            if ($submitted -gt $Now) { $firstSeen = $Now }
            $lastProgressAt = $Now
        }

        $ageMinutes  = [math]::Round(($Now - $firstSeen).TotalMinutes, 2)
        $idleMinutes = [math]::Round(($Now - $lastProgressAt).TotalMinutes, 2)
        $isMoving    = Test-PQCStatus $status @('Printing', 'Spooling')

        $action = 'keep'
        $reason = ''

        if (Test-PQCStatus $status @('Deleting')) {
            # "בתהליך מחיקה" שנתקע הוא המקרה הקלאסי שחוסם את כל התור
            if ($ageMinutes -ge $Settings.errorGraceMinutes) {
                $action = 'delete'; $reason = "תקועה במחיקה $ageMinutes דק'"
            } else { $reason = 'בתהליך מחיקה — ממתין' }
        }
        elseif (Test-PQCStatus $status @('Error', 'Offline', 'Blocked')) {
            if ($Settings.deleteOnError) {
                if ($ageMinutes -ge $Settings.errorGraceMinutes) {
                    $action = 'delete'; $reason = "שגיאה / מדפסת לא מחוברת ($status) $ageMinutes דק'"
                } else { $reason = 'שגיאה — בזמן חסד' }
            } else { $reason = 'שגיאה — מחיקה כבויה בהגדרות' }
        }
        elseif (Test-PQCStatus $status @('PaperOut', 'UserIntervention')) {
            if ($Settings.deletePaperOut -and $ageMinutes -ge $Settings.errorGraceMinutes) {
                $action = 'delete'; $reason = "ממתינה לנייר / להתערבות $ageMinutes דק'"
            } else { $reason = 'ממתינה לנייר או להתערבות — לא נוגעים' }
        }
        elseif (Test-PQCStatus $status @('Paused')) {
            if ($Settings.deletePaused -and $idleMinutes -ge $Settings.minutesNoProgress) {
                $action = 'delete'; $reason = "מושהית $idleMinutes דק'"
            } else { $reason = 'מושהית ביודעין — לא נוגעים' }
        }
        elseif ((-not $isMoving) -and (Test-PQCStatus $status @('Printed', 'Complete', 'Retained'))) {
            if ($Settings.deletePrintedLeftovers -and $idleMinutes -ge $Settings.printedLeftoverMinutes) {
                $action = 'delete'; $reason = "הודפסה ונותרה בתור $idleMinutes דק'"
            } else { $reason = 'הודפסה — ממתין לפני ניקוי' }
        }
        else {
            if ($idleMinutes -ge $Settings.minutesNoProgress) {
                $action = 'delete'; $reason = "ללא התקדמות $idleMinutes דק' (עמודים: $pages)"
            } else { $reason = "מתקדמת כרגע (עמודים: $pages)" }
        }

        $decisions += [pscustomobject]@{
            key         = $key
            printer     = [string]$job.PrinterName
            id          = $job.Id
            document    = [string]$job.DocumentName
            user        = [string]$job.UserName
            status      = $status
            pages       = $pages
            totalPages  = $job.TotalPages
            ageMinutes  = $ageMinutes
            idleMinutes = $idleMinutes
            progressed  = $progressed
            isMoving    = $isMoving
            attempts    = $attempts
            action      = $action
            reason      = $reason
        }

        $newState[$key] = [ordered]@{
            firstSeen      = $firstSeen.ToString('o')
            lastProgressAt = $lastProgressAt.ToString('o')
            pages          = $pages
            size           = $size
            status         = $status
            attempts       = $attempts
            printer        = [string]$job.PrinterName
            document       = [string]$job.DocumentName
        }
    }

    [pscustomobject]@{ decisions = $decisions; state = $newState }
}

# האם מותר לאפס את שירות ההדפסה כרגע? רק אם אין עבודה אחרת שבאמת זזה,
# אחרת האיפוס היה הורג הדפסה תקינה של מורה אחר באותו רגע.
function Test-PQCSpoolerResetAllowed {
    param([object[]]$Decisions, [object[]]$FailedKeys)
    foreach ($d in @($Decisions)) {
        if ($FailedKeys -contains $d.key) { continue }
        if ($d.isMoving -and $d.progressed) { return $false }
    }
    $true
}
