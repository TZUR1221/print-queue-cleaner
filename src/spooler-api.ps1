# spooler-api.ps1 — גישה ישירה לשירות ההדפסה של Windows דרך winspool.drv
#
# למה זה נדרש: הפקודה המובנית Remove-PrintJob עוברת דרך CIM ומחזירה
# "Access was denied" כשהיא לא רצה בהרשאות מנהל (אומת במחשב הזה, 24/11/2026).
# ה-API הישיר מצליח למחוק עבודה גם בהרשאות משתמש רגיל, כל עוד העבודה שלו.
# לכן הסדר הוא: קודם ה-API הישיר, ואם הוא נכשל — ניסיון דרך Remove-PrintJob.

if (-not ('PQCSpool' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PQCSpool {
    public const int PRINTER_ACCESS_USE        = 0x00000008;
    public const int PRINTER_ACCESS_ADMINISTER = 0x00000004;
    public const int PRINTER_ALL_ACCESS        = 0x000F000C;
    public const int JOB_CONTROL_PAUSE  = 1;
    public const int JOB_CONTROL_DELETE = 5;

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct PRINTER_DEFAULTS { public IntPtr pDatatype; public IntPtr pDevMode; public int DesiredAccess; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct DOCINFO { public string pDocName; public string pOutputFile; public string pDataType; }

    [DllImport("winspool.drv", SetLastError=true, CharSet=CharSet.Unicode, EntryPoint="OpenPrinterW")]
    public static extern bool OpenPrinter(string name, out IntPtr h, IntPtr def);
    [DllImport("winspool.drv", SetLastError=true, CharSet=CharSet.Unicode, EntryPoint="OpenPrinterW")]
    public static extern bool OpenPrinterEx(string name, out IntPtr h, ref PRINTER_DEFAULTS def);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool ClosePrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError=true, CharSet=CharSet.Unicode, EntryPoint="SetJobW")]
    public static extern bool SetJob(IntPtr h, int jobId, int level, IntPtr pJob, int command);
    [DllImport("winspool.drv", SetLastError=true, CharSet=CharSet.Unicode, EntryPoint="StartDocPrinterW")]
    public static extern int StartDocPrinter(IntPtr h, int level, ref DOCINFO di);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool EndDocPrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool StartPagePrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool EndPagePrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool WritePrinter(IntPtr h, byte[] buf, int count, out int written);
}
'@
}

# פתיחת תור הדפסה. מנסה קודם הרשאת ניהול (נדרשת למחיקת עבודות של משתמשים אחרים),
# ואם אין — חוזר להרשאה הרגילה שמספיקה לעבודות של המשתמש עצמו.
function Open-PQCPrinter {
    param([string]$PrinterName)
    $h = [IntPtr]::Zero
    $pd = New-Object PQCSpool+PRINTER_DEFAULTS
    $pd.pDatatype = [IntPtr]::Zero
    $pd.pDevMode  = [IntPtr]::Zero
    $pd.DesiredAccess = [PQCSpool]::PRINTER_ALL_ACCESS
    if ([PQCSpool]::OpenPrinterEx($PrinterName, [ref]$h, [ref]$pd)) { return $h }
    $pd.DesiredAccess = [PQCSpool]::PRINTER_ACCESS_USE
    if ([PQCSpool]::OpenPrinterEx($PrinterName, [ref]$h, [ref]$pd)) { return $h }
    if ([PQCSpool]::OpenPrinter($PrinterName, [ref]$h, [IntPtr]::Zero)) { return $h }
    throw ("פתיחת התור '{0}' נכשלה (קוד {1})" -f $PrinterName, [Runtime.InteropServices.Marshal]::GetLastWin32Error())
}

# מחיקת עבודה. מחזיר אובייקט עם ok / method / error — כדי שהיומן יוכל לומר איך זה נמחק.
function Remove-PQCPrintJob {
    param([string]$PrinterName, [int]$JobId)

    $nativeErr = $null
    $h = [IntPtr]::Zero
    try {
        $h = Open-PQCPrinter -PrinterName $PrinterName
        if ([PQCSpool]::SetJob($h, $JobId, 0, [IntPtr]::Zero, [PQCSpool]::JOB_CONTROL_DELETE)) {
            return [pscustomobject]@{ ok = $true; method = 'winspool'; error = $null }
        }
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        # קוד 1168 = האובייקט לא נמצא, כלומר העבודה כבר איננה. זו הצלחה לכל דבר.
        if ($code -eq 1168) { return [pscustomobject]@{ ok = $true; method = 'winspool (כבר לא בתור)'; error = $null } }
        $nativeErr = "SetJob נכשל (קוד $code)"
    } catch {
        $nativeErr = $_.Exception.Message
    } finally {
        if ($h -ne [IntPtr]::Zero) { [void][PQCSpool]::ClosePrinter($h) }
    }

    # גיבוי: הפקודה המובנית. דורשת הרשאות מנהל, אך לפעמים מצליחה היכן שה-API נכשל.
    try {
        Remove-PrintJob -PrinterName $PrinterName -ID $JobId -ErrorAction Stop
        return [pscustomobject]@{ ok = $true; method = 'Remove-PrintJob'; error = $null }
    } catch {
        return [pscustomobject]@{ ok = $false; method = 'שניהם נכשלו'; error = ("$nativeErr ; Remove-PrintJob: " + $_.Exception.Message) }
    }
}

# יצירת עבודת הדפסה מושהית — לשימוש בבדיקות בלבד.
# העבודה מושהית לפני שהמדפסת מקבלת אותה, כך שלא מודפס שום נייר.
function New-PQCPausedTestJob {
    param([string]$PrinterName, [string]$DocName = 'בדיקת איפוס תור — אין להדפיס')
    $h = Open-PQCPrinter -PrinterName $PrinterName
    try {
        $di = New-Object PQCSpool+DOCINFO
        $di.pDocName  = $DocName
        $di.pDataType = 'RAW'
        $jobId = [PQCSpool]::StartDocPrinter($h, 1, [ref]$di)
        if ($jobId -eq 0) { throw 'StartDocPrinter נכשל' }
        [void][PQCSpool]::SetJob($h, $jobId, 0, [IntPtr]::Zero, [PQCSpool]::JOB_CONTROL_PAUSE)
        [void][PQCSpool]::StartPagePrinter($h)
        $bytes = [System.Text.Encoding]::ASCII.GetBytes("INTEGRATION TEST - DO NOT PRINT`r`n")
        $w = 0
        [void][PQCSpool]::WritePrinter($h, $bytes, $bytes.Length, [ref]$w)
        [void][PQCSpool]::EndPagePrinter($h)
        [void][PQCSpool]::EndDocPrinter($h)
        $jobId
    } finally { [void][PQCSpool]::ClosePrinter($h) }
}
