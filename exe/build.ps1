# build.ps1 — מקמפל את ה-exe. אין צורך ב-Visual Studio ולא ב-dotnet SDK:
# csc.exe של .NET Framework 4.8 מגיע מובנה בכל Windows 10/11.
#
#   powershell -ExecutionPolicy Bypass -File exe\build.ps1
#   powershell -ExecutionPolicy Bypass -File exe\build.ps1 -SkipTests
#
# הפלט: exe\dist\PrintQueueCleaner.exe — קובץ אחד, בלי תלויות.

param(
    [switch]$SkipTests,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $here 'dist' }
$exePath = Join-Path $OutDir 'PrintQueueCleaner.exe'

$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) {
    $csc = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $csc)) {
    throw 'לא נמצא csc.exe של .NET Framework 4. דרוש Windows עם .NET Framework 4.x.'
}

if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$sources = @(
    'Program.cs', 'MainForm.cs', 'Engine.cs', 'Spooler.cs',
    'Storage.cs', 'Scanner.cs', 'TaskInstaller.cs', 'SelfTest.cs'
) | ForEach-Object {
    $p = Join-Path $here $_
    if (-not (Test-Path -LiteralPath $p)) { throw "חסר קובץ מקור: $_" }
    $p
}

$refs = @(
    'System.dll', 'System.Core.dll', 'System.Drawing.dll',
    'System.Windows.Forms.dll', 'System.ServiceProcess.dll'
)

$manifest = Join-Path $here 'app.manifest'
$icon     = Join-Path $here 'app.ico'

# winexe ולא exe: אחרת היה נפתח חלון קונסולה שחור בכל סריקה ברקע.
# הפלט לשורת הפקודה מטופל ב-Program.cs דרך AttachConsole.
# בלי /langversion: ה-csc המובנה הוא C# 5. זה מכוון — כך הבנייה עובדת
# בכל מחשב Windows בלי Visual Studio ובלי dotnet SDK. המקור כאן נכתב
# לפי C# 5 (בלי exception filters, בלי string interpolation).
$cscArgs = @(
    '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+',
    "/out:$exePath",
    "/win32manifest:$manifest"
)
if (Test-Path -LiteralPath $icon) { $cscArgs += "/win32icon:$icon" }
$cscArgs += ($refs | ForEach-Object { "/reference:$_" })
$cscArgs += $sources

Write-Host 'מקמפל...' -ForegroundColor Cyan
$out = & $csc @cscArgs 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Host $out -ForegroundColor Red
    throw "הקומפילציה נכשלה (קוד $LASTEXITCODE)."
}
if ($out.Trim()) { Write-Host $out.Trim() -ForegroundColor Yellow }

$f = Get-Item -LiteralPath $exePath
Write-Host ''
Write-Host ("נבנה: {0}" -f $f.FullName) -ForegroundColor Green
Write-Host ("גודל: {0} ק""ב" -f [math]::Round($f.Length / 1KB, 1))

if ($SkipTests) { return }

# ה-exe נבנה כ-winexe, ולכן PowerShell לא ממתין לו ולא קולט את הפלט שלו
# דרך & רגיל. Start-Process -Wait עם הפניה לקובץ פותר את שניהם.
function Invoke-Exe {
    param([string]$Label, [string[]]$ExeArgs)
    Write-Host $Label -ForegroundColor Cyan
    $o = Join-Path $env:TEMP ('pqc-out-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    $p = Start-Process -FilePath $exePath -ArgumentList $ExeArgs -Wait -PassThru `
                       -NoNewWindow -RedirectStandardOutput $o
    if (Test-Path -LiteralPath $o) {
        Get-Content -LiteralPath $o -Encoding UTF8 | ForEach-Object { Write-Host $_ }
        Remove-Item -LiteralPath $o -Force -ErrorAction SilentlyContinue
    }
    if ($p.ExitCode -ne 0) { throw "$Label נכשל (קוד $($p.ExitCode))." }
}

Write-Host ''
Invoke-Exe 'מריץ את הבדיקות שבתוך ה-exe...' @('--selftest')
Invoke-Exe 'בודק שהחלון נבנה...' @('--formcheck')

Write-Host ''
Write-Host 'הכל עבר.' -ForegroundColor Green
