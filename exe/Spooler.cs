// Spooler.cs — גישה ישירה לשירות ההדפסה של Windows (winspool.drv).
//
// למה לא דרך הפקודות המובנות: Remove-PrintJob עובר ב-CIM ומחזיר
// "Access denied" בלי הרשאות מנהל, גם על עבודה של המשתמש עצמו.
// ה-API הישיר מצליח. (אומת 24/11/2026.)
//
// יתרון נוסף על גרסת ה-PowerShell: כאן מצב העבודה מגיע כדגלי ביטים
// אמיתיים ולא כמחרוזת שצריך לחפש בה מילים.

using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace PrintQueueCleaner
{
    [Flags]
    internal enum JobStatus : uint
    {
        None = 0,
        Paused = 0x00000001,
        Error = 0x00000002,
        Deleting = 0x00000004,
        Spooling = 0x00000008,
        Printing = 0x00000010,
        Offline = 0x00000020,
        PaperOut = 0x00000040,
        Printed = 0x00000080,
        Deleted = 0x00000100,
        BlockedDevQ = 0x00000200,
        UserIntervention = 0x00000400,
        Restart = 0x00000800,
        Complete = 0x00001000,
        Retained = 0x00002000,
        RenderingLocally = 0x00004000
    }

    internal sealed class PrintJobInfo
    {
        public string PrinterName;
        public uint JobId;
        public string Document;
        public string UserName;
        public JobStatus Status;
        public uint TotalPages;
        public uint PagesPrinted;
        public uint Size;
        public DateTime Submitted;      // זמן מקומי

        public string Key
        {
            get { return PrinterName + "|" + JobId + "|" + Submitted.Ticks; }
        }

        // תיאור קריא לעברית, לצורך היומן והמסך
        public string StatusText
        {
            get
            {
                var parts = new List<string>();
                if ((Status & JobStatus.Printing) != 0) parts.Add("מדפיסה");
                if ((Status & JobStatus.Spooling) != 0) parts.Add("נשלחת");
                if ((Status & JobStatus.Paused) != 0) parts.Add("מושהית");
                if ((Status & JobStatus.Error) != 0) parts.Add("שגיאה");
                if ((Status & JobStatus.Offline) != 0) parts.Add("המדפסת לא מחוברת");
                if ((Status & JobStatus.PaperOut) != 0) parts.Add("חסר נייר");
                if ((Status & JobStatus.UserIntervention) != 0) parts.Add("דרושה התערבות");
                if ((Status & JobStatus.BlockedDevQ) != 0) parts.Add("חסומה");
                if ((Status & JobStatus.Deleting) != 0) parts.Add("בתהליך מחיקה");
                if ((Status & JobStatus.Printed) != 0) parts.Add("הודפסה");
                if ((Status & JobStatus.Complete) != 0) parts.Add("הושלמה");
                if ((Status & JobStatus.Retained) != 0) parts.Add("נשמרת בתור");
                if (parts.Count == 0) parts.Add("ממתינה");
                return string.Join(", ", parts.ToArray());
            }
        }
    }

    internal static class Spooler
    {
        private const int PRINTER_ACCESS_USE = 0x00000008;
        private const int PRINTER_ALL_ACCESS = 0x000F000C;
        private const int JOB_CONTROL_DELETE = 5;
        private const int JOB_CONTROL_PAUSE = 1;
        private const int ERROR_INSUFFICIENT_BUFFER = 122;
        private const int ERROR_NOT_FOUND = 1168;

        [StructLayout(LayoutKind.Sequential)]
        private struct PRINTER_DEFAULTS
        {
            public IntPtr pDatatype;
            public IntPtr pDevMode;
            public int DesiredAccess;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SYSTEMTIME
        {
            public ushort wYear, wMonth, wDayOfWeek, wDay, wHour, wMinute, wSecond, wMilliseconds;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct JOB_INFO_2
        {
            public uint JobId;
            public string pPrinterName;
            public string pMachineName;
            public string pUserName;
            public string pDocument;
            public string pNotifyName;
            public string pDatatype;
            public string pPrintProcessor;
            public string pParameters;
            public string pDriverName;
            public IntPtr pDevMode;
            public string pStatus;
            public IntPtr pSecurityDescriptor;
            public uint Status;
            public uint Priority;
            public uint Position;
            public uint StartTime;
            public uint UntilTime;
            public uint TotalPages;
            public uint Size;
            public SYSTEMTIME Submitted;
            public uint Time;
            public uint PagesPrinted;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DOCINFO
        {
            public string pDocName;
            public string pOutputFile;
            public string pDataType;
        }

        [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "OpenPrinterW")]
        private static extern bool OpenPrinter(string name, out IntPtr handle, ref PRINTER_DEFAULTS defaults);

        [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "OpenPrinterW")]
        private static extern bool OpenPrinterSimple(string name, out IntPtr handle, IntPtr defaults);

        [DllImport("winspool.drv", SetLastError = true)]
        private static extern bool ClosePrinter(IntPtr handle);

        [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "EnumJobsW")]
        private static extern bool EnumJobs(IntPtr handle, uint firstJob, uint noJobs, uint level,
                                            IntPtr pJob, uint cbBuf, out uint pcbNeeded, out uint pcReturned);

        [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "SetJobW")]
        private static extern bool SetJob(IntPtr handle, uint jobId, uint level, IntPtr pJob, uint command);

        [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "StartDocPrinterW")]
        private static extern int StartDocPrinter(IntPtr handle, int level, ref DOCINFO di);

        [DllImport("winspool.drv", SetLastError = true)]
        private static extern bool EndDocPrinter(IntPtr handle);

        [DllImport("winspool.drv", SetLastError = true)]
        private static extern bool StartPagePrinter(IntPtr handle);

        [DllImport("winspool.drv", SetLastError = true)]
        private static extern bool EndPagePrinter(IntPtr handle);

        [DllImport("winspool.drv", SetLastError = true)]
        private static extern bool WritePrinter(IntPtr handle, byte[] buf, int count, out int written);

        // פתיחת תור: קודם בהרשאת ניהול (נדרשת לעבודות של משתמשים אחרים),
        // ואם אין — בהרשאה רגילה שמספיקה לעבודות של המשתמש עצמו.
        private static IntPtr Open(string printerName)
        {
            IntPtr h;
            var pd = new PRINTER_DEFAULTS
            {
                pDatatype = IntPtr.Zero,
                pDevMode = IntPtr.Zero,
                DesiredAccess = PRINTER_ALL_ACCESS
            };
            if (OpenPrinter(printerName, out h, ref pd)) return h;

            pd.DesiredAccess = PRINTER_ACCESS_USE;
            if (OpenPrinter(printerName, out h, ref pd)) return h;

            if (OpenPrinterSimple(printerName, out h, IntPtr.Zero)) return h;

            throw new InvalidOperationException(string.Format(
                "פתיחת התור '{0}' נכשלה (קוד {1})", printerName, Marshal.GetLastWin32Error()));
        }

        public static List<string> InstalledPrinters()
        {
            var list = new List<string>();
            foreach (string name in System.Drawing.Printing.PrinterSettings.InstalledPrinters)
                list.Add(name);
            return list;
        }

        public static List<PrintJobInfo> GetJobs(string printerName)
        {
            var result = new List<PrintJobInfo>();
            IntPtr h = IntPtr.Zero;
            try { h = Open(printerName); }
            catch { return result; }

            IntPtr buffer = IntPtr.Zero;
            try
            {
                uint needed, returned;
                // סבב ראשון בלי חוצץ, רק כדי לדעת כמה זיכרון דרוש
                EnumJobs(h, 0, 0xFFFFFFFF, 2, IntPtr.Zero, 0, out needed, out returned);
                if (needed == 0) return result;

                buffer = Marshal.AllocHGlobal((int)needed);
                if (!EnumJobs(h, 0, 0xFFFFFFFF, 2, buffer, needed, out needed, out returned))
                    return result;

                int size = Marshal.SizeOf(typeof(JOB_INFO_2));
                for (uint i = 0; i < returned; i++)
                {
                    var p = new IntPtr(buffer.ToInt64() + i * size);
                    var ji = (JOB_INFO_2)Marshal.PtrToStructure(p, typeof(JOB_INFO_2));
                    result.Add(new PrintJobInfo
                    {
                        PrinterName = printerName,
                        JobId = ji.JobId,
                        Document = ji.pDocument ?? "(בלי שם)",
                        UserName = ji.pUserName ?? "",
                        Status = (JobStatus)ji.Status,
                        TotalPages = ji.TotalPages,
                        PagesPrinted = ji.PagesPrinted,
                        Size = ji.Size,
                        Submitted = ToLocalTime(ji.Submitted)
                    });
                }
            }
            finally
            {
                if (buffer != IntPtr.Zero) Marshal.FreeHGlobal(buffer);
                ClosePrinter(h);
            }
            return result;
        }

        private static DateTime ToLocalTime(SYSTEMTIME st)
        {
            // Submitted מגיע ב-UTC. שנה 0 = השדה לא מולא.
            if (st.wYear < 1601) return DateTime.Now;
            try
            {
                return new DateTime(st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute,
                                    st.wSecond, st.wMilliseconds, DateTimeKind.Utc).ToLocalTime();
            }
            catch { return DateTime.Now; }
        }

        public sealed class DeleteResult
        {
            public bool Ok;
            public string Method;
            public string Error;
        }

        public static DeleteResult DeleteJob(string printerName, uint jobId)
        {
            IntPtr h = IntPtr.Zero;
            try
            {
                h = Open(printerName);
                if (SetJob(h, jobId, 0, IntPtr.Zero, JOB_CONTROL_DELETE))
                    return new DeleteResult { Ok = true, Method = "winspool" };

                int code = Marshal.GetLastWin32Error();
                // 1168 = האובייקט לא נמצא, כלומר העבודה כבר איננה. הצלחה לכל דבר.
                if (code == ERROR_NOT_FOUND)
                    return new DeleteResult { Ok = true, Method = "winspool (כבר לא בתור)" };

                return new DeleteResult
                {
                    Ok = false,
                    Method = "winspool",
                    Error = "SetJob נכשל (קוד " + code + ")"
                };
            }
            catch (Exception ex)
            {
                return new DeleteResult { Ok = false, Method = "winspool", Error = ex.Message };
            }
            finally
            {
                if (h != IntPtr.Zero) ClosePrinter(h);
            }
        }

        // יצירת עבודה מושהית — לבדיקה בלבד. ההשהיה מתבצעת לפני הכתיבה,
        // כך שהמדפסת לא מקבלת כלום ולא מודפס נייר.
        public static uint CreatePausedTestJob(string printerName, string docName)
        {
            IntPtr h = Open(printerName);
            try
            {
                var di = new DOCINFO { pDocName = docName, pOutputFile = null, pDataType = "RAW" };
                int jobId = StartDocPrinter(h, 1, ref di);
                if (jobId == 0) throw new InvalidOperationException("StartDocPrinter נכשל");

                SetJob(h, (uint)jobId, 0, IntPtr.Zero, JOB_CONTROL_PAUSE);
                StartPagePrinter(h);
                byte[] bytes = System.Text.Encoding.ASCII.GetBytes("SELFTEST - DO NOT PRINT\r\n");
                int written;
                WritePrinter(h, bytes, bytes.Length, out written);
                EndPagePrinter(h);
                EndDocPrinter(h);
                return (uint)jobId;
            }
            finally { ClosePrinter(h); }
        }
    }
}
