# common.ps1 — תשתית משותפת: נתיבים, הגדרות, יומן ומצב
# הקובץ נטען בנקודה (dot-source) מתוך clear-queue.ps1, settings-ui.ps1 ו-install-task.ps1
# חובה: כל קובץ ps1 כאן שמור בקידוד UTF-8 עם BOM, אחרת PowerShell 5.1 שובר את העברית.

$PQCRoot         = Split-Path -Parent $PSScriptRoot
# אפשר להפנות את תיקיית הנתונים למקום אחר (משמש בבדיקת האמת, כדי לא לגעת בהגדרות החיות)
if ($PQCDataDirOverride) { $PQCDataDir = $PQCDataDirOverride } else { $PQCDataDir = Join-Path $PQCRoot 'data' }
$PQCLogDir       = Join-Path $PQCDataDir 'logs'
$PQCSettingsPath = Join-Path $PQCDataDir 'settings.json'
$PQCStatePath    = Join-Path $PQCDataDir 'state.json'
$PQCStatusPath   = Join-Path $PQCDataDir 'last-run.json'
$PQCTaskName     = 'PrintQueueCleaner'

function Initialize-PQCFolders {
    foreach ($d in @($PQCDataDir, $PQCLogDir)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

# ---------- הגדרות ----------

function Get-PQCDefaultSettings {
    [ordered]@{
        # האם המנוע פעיל בכלל. כיבוי כאן עוצר הכל בלי להסיר את המשימה המתוזמנת.
        enabled                   = $true
        # מצב סימולציה: רושם ביומן מה היה נמחק, בלי למחוק באמת.
        dryRun                    = $false
        # רשימת שמות המדפסות שבטיפול. רשימה ריקה = כל המדפסות במחשב.
        printers                  = @()
        # עבודה שלא התקדמה (לא הדפיסה עוד עמוד) יותר מכך — נמחקת.
        minutesNoProgress         = 5
        # זמן חסד לפני מחיקת עבודה שנמצאת בשגיאה, כדי לא להרוג תקלה רגעית.
        errorGraceMinutes         = 1
        deleteOnError             = $true
        # ממתינה לנייר / להתערבות אנושית — כברירת מחדל לא נוגעים, שמישהו ימלא נייר.
        deletePaperOut            = $false
        # עבודה שהמשתמש השהה בכוונה — כברירת מחדל לא נוגעים.
        deletePaused              = $false
        # עבודות שכבר הודפסו ונשארו תקועות בתור (הגדרת "שמור מסמכים מודפסים").
        deletePrintedLeftovers    = $true
        printedLeftoverMinutes    = 10
        # עבודה שמסרבת להימחק — איפוס שירות ההדפסה כמוצא אחרון.
        spoolerResetEnabled       = $true
        spoolerResetAfterAttempts = 3
        logKeepDays               = 60
    }
}

function Get-PQCSettings {
    Initialize-PQCFolders
    $defaults = Get-PQCDefaultSettings
    if (-not (Test-Path -LiteralPath $PQCSettingsPath)) {
        Save-PQCSettings $defaults
        return $defaults
    }
    $raw = $null
    try {
        $raw = Get-Content -LiteralPath $PQCSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-PQCLog "קובץ ההגדרות פגום — חוזר לברירות המחדל. ($($_.Exception.Message))" 'שגיאה'
        return $defaults
    }
    # מיזוג: מפתח חדש שנוסף בגרסה חדשה מקבל את ברירת המחדל שלו
    $merged = [ordered]@{}
    foreach ($k in $defaults.Keys) {
        if ($null -ne $raw -and $raw.PSObject.Properties.Name -contains $k -and $null -ne $raw.$k) {
            $merged[$k] = $raw.$k
        } else {
            $merged[$k] = $defaults[$k]
        }
    }
    # printers חייב להיות תמיד מערך, גם כשיש בו פריט אחד
    $merged['printers'] = @($merged['printers'] | Where-Object { $_ })
    $merged
}

function Save-PQCSettings($Settings) {
    Initialize-PQCFolders
    $json = $Settings | ConvertTo-Json -Depth 5
    Set-PQCFileUtf8 -Path $PQCSettingsPath -Text $json
}

# כתיבה אטומית ב-UTF-8: קודם לקובץ זמני ליד המקור, ואז החלפה.
# כך כשל קידוד או נפילה באמצע לא משאירים קובץ באפס בתים.
function Set-PQCFileUtf8 {
    param([string]$Path, [string]$Text)
    $tmp = "$Path.tmp"
    # הקידוד נעשה לפני שנוגעים בקובץ היעד, וההחלפה היא שינוי-שם באותו כונן
    [System.IO.File]::WriteAllText($tmp, $Text, (New-Object System.Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $Path) {
        # [NullString]::Value ולא $null — PowerShell הופך $null למחרוזת ריקה ש-.NET פוסל
        [System.IO.File]::Replace($tmp, $Path, [NullString]::Value)
    } else {
        [System.IO.File]::Move($tmp, $Path)
    }
}

# ---------- מצב (מעקב התקדמות בין הרצות) ----------

function Get-PQCState {
    if (-not (Test-Path -LiteralPath $PQCStatePath)) { return @{} }
    try {
        $obj = Get-Content -LiteralPath $PQCStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $h = @{}
        if ($null -ne $obj) {
            foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = $p.Value }
        }
        return $h
    } catch { return @{} }
}

function Save-PQCState($State) {
    Initialize-PQCFolders
    $json = ([pscustomobject]$State) | ConvertTo-Json -Depth 5
    Set-PQCFileUtf8 -Path $PQCStatePath -Text $json
}

# ---------- יומן ----------

function Write-PQCLog {
    param([string]$Message, [string]$Level = 'מידע')
    Initialize-PQCFolders
    $line = '{0}  [{1}]  {2}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'), $Level, $Message
    $file = Join-Path $PQCLogDir ('queue-{0}.log' -f (Get-Date -Format 'yyyy-MM'))
    # שתי הרצות יכולות להיפגש; ננסה כמה פעמים ולא נפיל את הריצה בגלל היומן
    for ($i = 0; $i -lt 5; $i++) {
        try {
            $sw = New-Object System.IO.StreamWriter($file, $true, (New-Object System.Text.UTF8Encoding $false))
            try { $sw.WriteLine($line) } finally { $sw.Dispose() }
            break
        } catch { Start-Sleep -Milliseconds 120 }
    }
}

function Get-PQCLogTail {
    param([int]$Lines = 60)
    if (-not (Test-Path -LiteralPath $PQCLogDir)) { return @() }
    $file = Get-ChildItem -LiteralPath $PQCLogDir -Filter 'queue-*.log' -File -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
    if (-not $file) { return @() }
    try { Get-Content -LiteralPath $file.FullName -Encoding UTF8 -Tail $Lines } catch { @() }
}

function Remove-PQCOldLogs {
    param([int]$KeepDays = 60)
    if (-not (Test-Path -LiteralPath $PQCLogDir)) { return }
    $cutoff = (Get-Date).AddDays(-1 * [math]::Abs($KeepDays))
    Get-ChildItem -LiteralPath $PQCLogDir -Filter 'queue-*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# ---------- דיווח מצב להצגה בממשק ----------

function Save-PQCRunStatus($Status) {
    Initialize-PQCFolders
    $json = ([pscustomobject]$Status) | ConvertTo-Json -Depth 5
    Set-PQCFileUtf8 -Path $PQCStatusPath -Text $json
}

function Get-PQCRunStatus {
    if (-not (Test-Path -LiteralPath $PQCStatusPath)) { return $null }
    try { Get-Content -LiteralPath $PQCStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
}

function Test-PQCElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole(
        [System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
