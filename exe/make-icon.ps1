# make-icon.ps1 — מייצר את app.ico. מריצים פעם אחת; הקובץ נשמר בגיט.
#
# למה לא לקחת אייקון מוכן מ-Windows: אייקון שנשלף מ-imageres.dll הוא
# נכס של מיקרוסופט, ו-exe שמופץ לאנשים אחרים צריך סמל משלו.
# הציור הוא GDI+ טהור, בלי קבצים חיצוניים ובלי תלויות.
#
#   powershell -ExecutionPolicy Bypass -File exe\make-icon.ps1
#
# ⚠️ מלכודת שעלתה בבנייה: קובץ ICO שכל רשומותיו PNG נראה תקין אך
# System.Drawing.Icon.ToBitmap() זורק עליו "Requested range extends past
# the end of the array" — המחלקה אינה תומכת ברשומות PNG. הסייר תומך,
# אבל לא כל הקשר. לכן המבנה כאן הוא התקני: DIB קלאסי לגדלים הקטנים
# ו-PNG רק ל-256.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$out = Join-Path $PSScriptRoot 'app.ico'
$dibSizes = @(16, 32, 48, 64)
$pngSizes = @(256)

# מדפסת כחולה עם חץ מעגלי ירוק — "התור מתנקה מעצמו"
$bodyBlue   = [System.Drawing.Color]::FromArgb(255, 37, 99, 185)
$bodyDark   = [System.Drawing.Color]::FromArgb(255, 25, 70, 140)
$paperWhite = [System.Drawing.Color]::FromArgb(255, 252, 252, 254)
$arrowGreen = [System.Drawing.Color]::FromArgb(255, 34, 160, 80)

function New-Bitmap([int]$S) {
    $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)

    $u = $S / 32.0   # יחידת מידה: הציור תוכנן על רשת 32x32

    # הדף שיוצא מלמעלה
    $brPaper = New-Object System.Drawing.SolidBrush($paperWhite)
    $penDark = New-Object System.Drawing.Pen($bodyDark, [float]([Math]::Max(1.0, 1.2*$u)))
    $g.FillRectangle($brPaper, [float](6*$u), [float](2*$u), [float](15*$u), [float](9*$u))
    $g.DrawRectangle($penDark, [float](6*$u), [float](2*$u), [float](15*$u), [float](9*$u))

    # שורות טקסט על הדף — רק כשיש מספיק פיקסלים שזה לא ייראה לכלוך
    if ($S -ge 32) {
        $brLine = New-Object System.Drawing.SolidBrush($bodyDark)
        for ($i = 0; $i -lt 3; $i++) {
            $y = 4.2*$u + $i * 2.2*$u
            $g.FillRectangle($brLine, [float](8*$u), [float]$y, [float](11*$u), [float]([Math]::Max(1.0, 0.9*$u)))
        }
        $brLine.Dispose()
    }

    # גוף המדפסת
    $brBody = New-Object System.Drawing.SolidBrush($bodyBlue)
    $g.FillRectangle($brBody, [float](2*$u), [float](11*$u), [float](22*$u), [float](11*$u))

    # חריץ הפלט
    $brSlot = New-Object System.Drawing.SolidBrush($bodyDark)
    $g.FillRectangle($brSlot, [float](5*$u), [float](18.5*$u), [float](14*$u), [float]([Math]::Max(1.0, 2*$u)))

    # נורית
    if ($S -ge 32) {
        $brLed = New-Object System.Drawing.SolidBrush($paperWhite)
        $g.FillEllipse($brLed, [float](20.5*$u), [float](13*$u), [float](2*$u), [float](2*$u))
        $brLed.Dispose()
    }

    # חץ מעגלי ירוק בפינה
    $badge = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,255,255,255))
    $g.FillEllipse($badge, [float](17*$u), [float](17*$u), [float](15*$u), [float](15*$u))
    $badge.Dispose()
    $arcRect = New-Object System.Drawing.RectangleF(([float](20*$u)), ([float](20*$u)), ([float](9*$u)), ([float](9*$u)))
    $penArrow = New-Object System.Drawing.Pen($arrowGreen, [float]([Math]::Max(1.5, 2.6*$u)))
    $penArrow.StartCap = 'Round'
    $g.DrawArc($penArrow, $arcRect, 20, 290)
    $tip = @(
        (New-Object System.Drawing.PointF(([float](30.0*$u)), ([float](21.5*$u)))),
        (New-Object System.Drawing.PointF(([float](26.0*$u)), ([float](22.3*$u)))),
        (New-Object System.Drawing.PointF(([float](29.2*$u)), ([float](25.6*$u))))
    )
    $brArrow = New-Object System.Drawing.SolidBrush($arrowGreen)
    $g.FillPolygon($brArrow, [System.Drawing.PointF[]]$tip)

    foreach ($d in @($brPaper, $penDark, $brBody, $brSlot, $penArrow, $brArrow)) { $d.Dispose() }
    $g.Dispose()
    return $bmp
}

# רשומת DIB של אייקון: BITMAPINFOHEADER שבו הגובה כפול (תמונה + מסכה),
# ואחריו פיקסלים BGRA משורה תחתונה למעלה, ואחריהם מסכת AND של ביט לפיקסל.
# השקיפות האמיתית יושבת בערוץ האלפא, ולכן המסכה כולה אפסים.
function Get-DibBytes([System.Drawing.Bitmap]$bmp) {
    $S = $bmp.Width
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)

    $maskRow = [int][Math]::Floor(($S + 31) / 32) * 4
    $bw.Write([uint32]40)            # biSize
    $bw.Write([int32]$S)             # biWidth
    $bw.Write([int32]($S * 2))       # biHeight — תמונה + מסכה
    $bw.Write([uint16]1)             # biPlanes
    $bw.Write([uint16]32)            # biBitCount
    $bw.Write([uint32]0)             # biCompression = BI_RGB
    $bw.Write([uint32]($S * $S * 4 + $maskRow * $S))   # biSizeImage
    $bw.Write([int32]0); $bw.Write([int32]0)           # רזולוציה
    $bw.Write([uint32]0); $bw.Write([uint32]0)         # לוח צבעים

    for ($y = $S - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $S; $x++) {
            $c = $bmp.GetPixel($x, $y)
            $bw.Write([byte]$c.B); $bw.Write([byte]$c.G)
            $bw.Write([byte]$c.R); $bw.Write([byte]$c.A)
        }
    }
    $bw.Write((New-Object byte[] ($maskRow * $S)))      # מסכת AND, אפסים

    $bw.Flush()
    $bytes = $ms.ToArray()
    $bw.Dispose(); $ms.Dispose()
    return $bytes
}

function Get-PngBytes([System.Drawing.Bitmap]$bmp) {
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $b = $ms.ToArray()
    $ms.Dispose()
    return $b
}

$entries = @()
foreach ($s in $dibSizes) {
    $bmp = New-Bitmap $s
    # [byte[]] מפורש: PowerShell מפרק מערך שפונקציה מחזירה ל-Object[]
    $entries += , @{ Size = $s; Bytes = [byte[]](Get-DibBytes $bmp); Kind = 'DIB' }
    $bmp.Dispose()
}
foreach ($s in $pngSizes) {
    $bmp = New-Bitmap $s
    $entries += , @{ Size = $s; Bytes = [byte[]](Get-PngBytes $bmp); Kind = 'PNG' }
    $bmp.Dispose()
}

# כותרת ICONDIR (6 בתים) + ICONDIRENTRY (16 בתים לכל גודל) + הנתונים
$fs = New-Object System.IO.FileStream($out, [System.IO.FileMode]::Create)
$bw = New-Object System.IO.BinaryWriter($fs)
try {
    $bw.Write([uint16]0)                 # reserved
    $bw.Write([uint16]1)                 # type = icon
    $bw.Write([uint16]$entries.Count)

    $offset = 6 + 16 * $entries.Count
    foreach ($e in $entries) {
        $dim = if ($e.Size -ge 256) { 0 } else { $e.Size }   # 0 פירושו 256
        $bw.Write([byte]$dim)
        $bw.Write([byte]$dim)
        $bw.Write([byte]0)               # צבעים בלוח
        $bw.Write([byte]0)               # reserved
        $bw.Write([uint16]1)             # מישורי צבע
        $bw.Write([uint16]32)            # ביטים לפיקסל
        $bw.Write([uint32]([byte[]]$e.Bytes).Length)
        $bw.Write([uint32]$offset)
        $offset += $e.Bytes.Length
    }
    foreach ($e in $entries) { $bw.Write([byte[]]$e.Bytes) }
}
finally { $bw.Dispose(); $fs.Dispose() }

$f = Get-Item -LiteralPath $out
Write-Host ("נוצר: {0}" -f $f.FullName) -ForegroundColor Green
Write-Host ("{0} גדלים, {1} ק""ב" -f $entries.Count, [math]::Round($f.Length/1KB,1))

# אימות אמיתי: לא רק שהקובץ נטען, אלא שאפשר להפוך אותו לתמונה בכל גודל.
# זו הבדיקה שתפסה את מלכודת ה-PNG.
foreach ($s in $dibSizes) {
    $ico = New-Object System.Drawing.Icon($out, $s, $s)
    $b = $ico.ToBitmap()
    if ($b.Width -ne $s) { throw "גודל $s חזר כ-$($b.Width)" }
    $b.Dispose(); $ico.Dispose()
    Write-Host ("  נבדק: {0}x{0} נטען ומומר לתמונה" -f $s)
}
