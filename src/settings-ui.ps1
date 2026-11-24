# settings-ui.ps1 — חלון ההגדרות בעברית. זה המסך היחיד שהמשתמש צריך.
# נפתח מהקובץ "הפעלה.bat" שבתיקיית הפרויקט (מבקש הרשאות מנהל).

# -SelfTest בונה את החלון, מדווח מה נבנה ויוצא בלי להציג אותו. לשימוש בבדיקות.
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$settings = Get-PQCSettings
$FontName = 'Segoe UI'

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 260, [int]$Size = 10, [bool]$Bold = $false)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Left = $X; $l.Top = $Y; $l.Width = $W; $l.Height = 22
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $l.Font = New-Object System.Drawing.Font($FontName, $Size, $style)
    $l
}

function New-Check {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 420, [bool]$Checked = $false)
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text; $c.Left = $X; $c.Top = $Y; $c.Width = $W; $c.Height = 24
    $c.Checked = $Checked
    $c.Font = New-Object System.Drawing.Font($FontName, 10)
    $c
}

function New-Num {
    param([int]$X, [int]$Y, [int]$Min, [int]$Max, [int]$Value)
    $n = New-Object System.Windows.Forms.NumericUpDown
    $n.Left = $X; $n.Top = $Y; $n.Width = 70
    $n.Minimum = $Min; $n.Maximum = $Max; $n.Value = [math]::Min([math]::Max($Value, $Min), $Max)
    $n.Font = New-Object System.Drawing.Font($FontName, 10)
    $n.TextAlign = 'Center'
    $n
}

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 150)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Left = $X; $b.Top = $Y; $b.Width = $W; $b.Height = 34
    $b.Font = New-Object System.Drawing.Font($FontName, 10)
    $b.FlatStyle = 'System'
    $b
}

# ---------- החלון ----------

$form = New-Object System.Windows.Forms.Form
$form.Text = 'איפוס תור הדפסות'
$form.Width = 700
$form.Height = 960
$form.StartPosition = 'CenterScreen'
$form.RightToLeft = 'Yes'
$form.RightToLeftLayout = $true
$form.AutoScroll = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 251)
$form.Font = New-Object System.Drawing.Font($FontName, 10)

$title = New-Label -Text 'איפוס תור הדפסות' -X 20 -Y 14 -W 400 -Size 16 -Bold $true
$sub   = New-Label -Text 'בודק את תורי ההדפסה כל 2 דקות ומוחק עבודות שנתקעו.' -X 20 -Y 46 -W 620 -Size 10
$sub.ForeColor = [System.Drawing.Color]::FromArgb(90, 95, 105)
$form.Controls.AddRange(@($title, $sub))

# --- מדפסות ---
$gpPrinters = New-Object System.Windows.Forms.GroupBox
$gpPrinters.Text = '  מדפסות שבטיפול  '
$gpPrinters.Left = 20; $gpPrinters.Top = 80; $gpPrinters.Width = 640; $gpPrinters.Height = 205
$gpPrinters.Font = New-Object System.Drawing.Font($FontName, 10, [System.Drawing.FontStyle]::Bold)
$gpPrinters.RightToLeft = 'Yes'

$clbPrinters = New-Object System.Windows.Forms.CheckedListBox
$clbPrinters.Left = 15; $clbPrinters.Top = 28; $clbPrinters.Width = 610; $clbPrinters.Height = 130
$clbPrinters.Font = New-Object System.Drawing.Font($FontName, 10)
$clbPrinters.RightToLeft = 'Yes'
$clbPrinters.CheckOnClick = $true

$allPrinters = @()
try { $allPrinters = @(Get-Printer -ErrorAction Stop | Sort-Object Name) } catch { }
foreach ($p in $allPrinters) {
    $label = '{0}    ({1})' -f $p.Name, $p.PortName
    $isOn = if (@($settings.printers).Count -eq 0) { $false } else { @($settings.printers) -contains $p.Name }
    [void]$clbPrinters.Items.Add($label, $isOn)
}

$btnAll  = New-Button -Text 'סמן הכל' -X 15 -Y 164 -W 110
$btnNone = New-Button -Text 'נקה הכל' -X 135 -Y 164 -W 110
$lblPrnHint = New-Label -Text 'אם לא סומנה אף מדפסת — המערכת תטפל בכל המדפסות.' -X 255 -Y 170 -W 370 -Size 9
$lblPrnHint.ForeColor = [System.Drawing.Color]::FromArgb(120, 125, 135)
$lblPrnHint.Font = New-Object System.Drawing.Font($FontName, 9)

$btnAll.Add_Click({ for ($i = 0; $i -lt $clbPrinters.Items.Count; $i++) { $clbPrinters.SetItemChecked($i, $true) } })
$btnNone.Add_Click({ for ($i = 0; $i -lt $clbPrinters.Items.Count; $i++) { $clbPrinters.SetItemChecked($i, $false) } })
$gpPrinters.Controls.AddRange(@($clbPrinters, $btnAll, $btnNone, $lblPrnHint))
$form.Controls.Add($gpPrinters)

# --- מתי למחוק ---
$gpRules = New-Object System.Windows.Forms.GroupBox
$gpRules.Text = '  מתי למחוק עבודה  '
$gpRules.Left = 20; $gpRules.Top = 292; $gpRules.Width = 640; $gpRules.Height = 215
$gpRules.Font = New-Object System.Drawing.Font($FontName, 10, [System.Drawing.FontStyle]::Bold)
$gpRules.RightToLeft = 'Yes'

$numNoProgress = New-Num -X 15 -Y 30 -Min 1 -Max 240 -Value ([int]$settings.minutesNoProgress)
$lblNoProgress = New-Label -Text 'דקות שעבודה עומדת בלי להתקדם — ואז נמחקת' -X 95 -Y 33 -W 400
$chkError      = New-Check -Text 'למחוק עבודה שנמצאת בשגיאה או שהמדפסת לא מחוברת' -X 15 -Y 64 -Checked ([bool]$settings.deleteOnError)
$numErrGrace   = New-Num -X 35 -Y 92 -Min 0 -Max 60 -Value ([int]$settings.errorGraceMinutes)
$lblErrGrace   = New-Label -Text 'דקות המתנה לפני מחיקת עבודה בשגיאה (למקרה של תקלה רגעית)' -X 115 -Y 95 -W 420 -Size 9
$lblErrGrace.Font = New-Object System.Drawing.Font($FontName, 9)
$chkPaperOut   = New-Check -Text 'למחוק גם עבודה שממתינה לנייר או להתערבות (לא מומלץ)' -X 15 -Y 120 -Checked ([bool]$settings.deletePaperOut)
$chkPaused     = New-Check -Text 'למחוק גם עבודה שמישהו השהה בכוונה (לא מומלץ)' -X 15 -Y 146 -Checked ([bool]$settings.deletePaused)
$chkPrinted    = New-Check -Text 'לנקות עבודות שכבר הודפסו ונשארו בתור, לאחר' -X 15 -Y 172 -W 330 -Checked ([bool]$settings.deletePrintedLeftovers)
$numPrinted    = New-Num -X 350 -Y 170 -Min 1 -Max 240 -Value ([int]$settings.printedLeftoverMinutes)
$lblPrinted    = New-Label -Text 'דקות' -X 425 -Y 173 -W 60

$chkError.Add_CheckedChanged({ $numErrGrace.Enabled = $chkError.Checked })
$numErrGrace.Enabled = $chkError.Checked
$chkPrinted.Add_CheckedChanged({ $numPrinted.Enabled = $chkPrinted.Checked })
$numPrinted.Enabled = $chkPrinted.Checked

$gpRules.Controls.AddRange(@($numNoProgress, $lblNoProgress, $chkError, $numErrGrace, $lblErrGrace,
                             $chkPaperOut, $chkPaused, $chkPrinted, $numPrinted, $lblPrinted))
$form.Controls.Add($gpRules)

# --- מקרים קשים ---
$gpHard = New-Object System.Windows.Forms.GroupBox
$gpHard.Text = '  עבודה שמסרבת להימחק  '
$gpHard.Left = 20; $gpHard.Top = 513; $gpHard.Width = 640; $gpHard.Height = 100
$gpHard.Font = New-Object System.Drawing.Font($FontName, 10, [System.Drawing.FontStyle]::Bold)
$gpHard.RightToLeft = 'Yes'

$chkSpooler = New-Check -Text 'לאפס את שירות ההדפסה של Windows אחרי' -X 15 -Y 30 -W 300 -Checked ([bool]$settings.spoolerResetEnabled)
$numSpooler = New-Num -X 320 -Y 28 -Min 1 -Max 20 -Value ([int]$settings.spoolerResetAfterAttempts)
$lblSpooler = New-Label -Text 'נסיונות מחיקה כושלים' -X 395 -Y 31 -W 200
$lblSpoolerHint = New-Label -Text 'איפוס השירות משוחרר עבודה נעולה, אך רק כשאין באותו רגע הדפסה שמתקדמת.' -X 15 -Y 60 -W 600 -Size 9
$lblSpoolerHint.Font = New-Object System.Drawing.Font($FontName, 9)
$lblSpoolerHint.ForeColor = [System.Drawing.Color]::FromArgb(120, 125, 135)
$numSpooler.Enabled = $chkSpooler.Checked
$chkSpooler.Add_CheckedChanged({ $numSpooler.Enabled = $chkSpooler.Checked })

$gpHard.Controls.AddRange(@($chkSpooler, $numSpooler, $lblSpooler, $lblSpoolerHint))
$form.Controls.Add($gpHard)

# --- מצב ---
$gpState = New-Object System.Windows.Forms.GroupBox
$gpState.Text = '  מצב המערכת  '
$gpState.Left = 20; $gpState.Top = 620; $gpState.Width = 640; $gpState.Height = 105
$gpState.Font = New-Object System.Drawing.Font($FontName, 10, [System.Drawing.FontStyle]::Bold)
$gpState.RightToLeft = 'Yes'

$chkEnabled = New-Check -Text 'המערכת פעילה' -X 15 -Y 28 -W 180 -Checked ([bool]$settings.enabled)
$chkDryRun  = New-Check -Text 'מצב בדיקה — רק לרשום ביומן, בלי למחוק באמת' -X 200 -Y 28 -W 420 -Checked ([bool]$settings.dryRun)
$lblStatus  = New-Label -Text 'בודק...' -X 15 -Y 58 -W 600 -Size 9
$lblStatus.Font = New-Object System.Drawing.Font($FontName, 9)
$lblStatus.Height = 40

$gpState.Controls.AddRange(@($chkEnabled, $chkDryRun, $lblStatus))
$form.Controls.Add($gpState)

# --- כפתורים ---
$btnSave    = New-Button -Text 'שמור הגדרות' -X 20 -Y 735 -W 140
$btnRunNow  = New-Button -Text 'בדוק עכשיו' -X 168 -Y 735 -W 120
$btnInstall = New-Button -Text 'הפעל כל 2 דקות' -X 296 -Y 735 -W 150
$btnRemove  = New-Button -Text 'בטל הרצה אוטומטית' -X 454 -Y 735 -W 160
$btnSave.BackColor = [System.Drawing.Color]::FromArgb(222, 235, 255)
$form.Controls.AddRange(@($btnSave, $btnRunNow, $btnInstall, $btnRemove))

# --- יומן ---
$lblLog = New-Label -Text 'יומן הפעולות האחרונות:' -X 20 -Y 779 -W 300 -Bold $true
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Left = 20; $txtLog.Top = 805; $txtLog.Width = 640; $txtLog.Height = 110
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'
$txtLog.RightToLeft = 'Yes'
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.BackColor = [System.Drawing.Color]::White
$btnOpenLog = New-Button -Text 'פתח את קובץ היומן' -X 500 -Y 773 -W 125
$form.Controls.AddRange(@($lblLog, $txtLog, $btnOpenLog))

# ---------- לוגיקת המסך ----------

function Get-UiSettings {
    $chosen = @()
    for ($i = 0; $i -lt $clbPrinters.Items.Count; $i++) {
        if ($clbPrinters.GetItemChecked($i)) { $chosen += $allPrinters[$i].Name }
    }
    # אם סומנו כל המדפסות — נשמור רשימה ריקה, שמשמעותה "כולן, גם מדפסת שתתווסף בעתיד"
    if ($chosen.Count -eq $clbPrinters.Items.Count) { $chosen = @() }

    [ordered]@{
        enabled                   = [bool]$chkEnabled.Checked
        dryRun                    = [bool]$chkDryRun.Checked
        printers                  = $chosen
        minutesNoProgress         = [int]$numNoProgress.Value
        errorGraceMinutes         = [int]$numErrGrace.Value
        deleteOnError             = [bool]$chkError.Checked
        deletePaperOut            = [bool]$chkPaperOut.Checked
        deletePaused              = [bool]$chkPaused.Checked
        deletePrintedLeftovers    = [bool]$chkPrinted.Checked
        printedLeftoverMinutes    = [int]$numPrinted.Value
        spoolerResetEnabled       = [bool]$chkSpooler.Checked
        spoolerResetAfterAttempts = [int]$numSpooler.Value
        logKeepDays               = [int]$settings.logKeepDays
    }
}

function Update-StatusLine {
    $parts = @()
    try {
        $t = & (Join-Path $PSScriptRoot 'install-task.ps1') -Action status
        if ($t.installed) {
            $every = if ($t.interval) { "כל $($t.interval) דקות" } else { 'בתזמון קבוע' }
            $parts += "הרצה אוטומטית: מותקנת ($every, מצב: $($t.state))"
            if ($t.lastRun -and $t.lastRun.Year -gt 1999) {
                $parts += "ריצה אחרונה: $(Get-Date $t.lastRun -Format 'dd/MM/yyyy HH:mm:ss')"
            }
        } else {
            $parts += 'הרצה אוטומטית: לא מותקנת — לחץ "הפעל כל 2 דקות"'
        }
    } catch { $parts += "לא ניתן לקרוא את מצב המשימה: $($_.Exception.Message)" }

    $r = Get-PQCRunStatus
    if ($r) {
        $when = try { Get-Date ([datetime]$r.time) -Format 'HH:mm:ss' } catch { '' }
        $parts += "סריקה אחרונה ב-$when : $($r.scanned) בתור, נמחקו $($r.deleted)"
    }
    if (-not (Test-PQCElevated)) { $parts += 'שים לב: החלון אינו בהרשאות מנהל — התקנה/הסרה של המשימה לא תעבוד.' }

    $lblStatus.Text = $parts -join '   |   '
}

function Update-LogBox {
    $lines = @(Get-PQCLogTail -Lines 80)
    if ($lines.Count -eq 0) { $txtLog.Text = 'אין רשומות ביומן עדיין.'; return }
    $txtLog.Lines = [string[]]($lines[($lines.Count - 1)..0])   # החדש למעלה
}

$btnSave.Add_Click({
    try {
        $s = Get-UiSettings
        Save-PQCSettings $s
        $script:settings = $s
        Write-PQCLog 'ההגדרות נשמרו מהמסך.' 'פעולה'
        Update-LogBox
        [System.Windows.Forms.MessageBox]::Show('ההגדרות נשמרו.', 'איפוס תור הדפסות',
            'OK', 'Information', 'Button1', 'RtlReading, RightAlign') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("השמירה נכשלה: $($_.Exception.Message)", 'שגיאה',
            'OK', 'Error', 'Button1', 'RtlReading, RightAlign') | Out-Null
    }
})

$btnRunNow.Add_Click({
    try {
        Save-PQCSettings (Get-UiSettings)
        $form.Cursor = 'WaitCursor'
        $out = & (Join-Path $PSScriptRoot 'clear-queue.ps1') 2>&1 | Out-String
        $form.Cursor = 'Default'
        Update-LogBox; Update-StatusLine
        [System.Windows.Forms.MessageBox]::Show($out.Trim(), 'תוצאת הבדיקה',
            'OK', 'Information', 'Button1', 'RtlReading, RightAlign') | Out-Null
    } catch {
        $form.Cursor = 'Default'
        [System.Windows.Forms.MessageBox]::Show("ההרצה נכשלה: $($_.Exception.Message)", 'שגיאה',
            'OK', 'Error', 'Button1', 'RtlReading, RightAlign') | Out-Null
    }
})

$btnInstall.Add_Click({
    try {
        Save-PQCSettings (Get-UiSettings)
        & (Join-Path $PSScriptRoot 'install-task.ps1') -Action install | Out-Null
        Update-StatusLine; Update-LogBox
        [System.Windows.Forms.MessageBox]::Show('ההרצה האוטומטית הותקנה. מעתה המחשב בודק את התור כל 2 דקות, גם כשאף אחד לא מחובר.',
            'איפוס תור הדפסות', 'OK', 'Information', 'Button1', 'RtlReading, RightAlign') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("ההתקנה נכשלה: $($_.Exception.Message)", 'שגיאה',
            'OK', 'Error', 'Button1', 'RtlReading, RightAlign') | Out-Null
    }
})

$btnRemove.Add_Click({
    try {
        & (Join-Path $PSScriptRoot 'install-task.ps1') -Action remove | Out-Null
        Update-StatusLine; Update-LogBox
        [System.Windows.Forms.MessageBox]::Show('ההרצה האוטומטית הוסרה.', 'איפוס תור הדפסות',
            'OK', 'Information', 'Button1', 'RtlReading, RightAlign') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("ההסרה נכשלה: $($_.Exception.Message)", 'שגיאה',
            'OK', 'Error', 'Button1', 'RtlReading, RightAlign') | Out-Null
    }
})

$btnOpenLog.Add_Click({
    $file = Join-Path $PQCLogDir ('queue-{0}.log' -f (Get-Date -Format 'yyyy-MM'))
    if (Test-Path -LiteralPath $file) { Start-Process notepad.exe $file }
    else {
        [System.Windows.Forms.MessageBox]::Show('אין עדיין קובץ יומן לחודש הזה.', 'איפוס תור הדפסות',
            'OK', 'Information', 'Button1', 'RtlReading, RightAlign') | Out-Null
    }
})

# רענון מצב ויומן כל 10 שניות, כדי שהמסך יראה את מה שהמשימה עושה ברקע
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 10000
$timer.Add_Tick({ Update-StatusLine; Update-LogBox })
$form.Add_Shown({ Update-StatusLine; Update-LogBox; $timer.Start() })
$form.Add_FormClosed({ $timer.Stop(); $timer.Dispose() })

if ($SelfTest) {
    $count = 0
    $walk = { param($c) foreach ($x in $c.Controls) { $script:count++; & $walk $x } }
    & $walk $form
    Write-Output ("החלון נבנה בהצלחה: {0} פקדים, גודל {1}x{2}, מדפסות ברשימה: {3}" -f `
                  $count, $form.Width, $form.Height, $clbPrinters.Items.Count)
    Update-StatusLine
    Write-Output ("שורת המצב: " + $lblStatus.Text)
    $form.Dispose()
    exit 0
}

[void]$form.ShowDialog()
