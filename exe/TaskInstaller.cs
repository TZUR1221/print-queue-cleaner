// TaskInstaller.cs — התקנה / הסרה / זיהוי של ההרצה האוטומטית כל 2 דקות.
// המשימה רצה תחת SYSTEM, כדי שתעבוד גם כשאף אחד לא מחובר למחשב
// וכדי שתהיה לה הרשאה למחוק עבודות של כל המשתמשים.

using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace PrintQueueCleaner
{
    internal sealed class TaskState
    {
        public bool Installed;
        public bool DetailsReadable;   // false = קיימת אך דרושות הרשאות מנהל לקריאת הפרטים
        public string Error;
    }

    internal static class TaskInstaller
    {
        public static string TaskName = "PrintQueueCleaner";
        public const int IntervalMinutes = 2;

        private static string ExePath
        {
            get { return Process.GetCurrentProcess().MainModule.FileName; }
        }

        public static void Install()
        {
            if (!Storage.IsElevated())
                throw new InvalidOperationException("התקנת ההרצה האוטומטית דורשת הרשאות מנהל.");

            // אם ההגדרות הופנו לתיקייה אחרת, המשימה חייבת לקבל את אותה
            // הפניה — אחרת היא תרוץ על ברירת המחדל והמשתמש יראה שתי
            // מערכות שלא מדברות זו עם זו.
            string tr = "\"" + ExePath + "\" --scan";
            if (Storage.DataDirWasOverridden)
                tr += " --data \"" + Storage.DataDir + "\"";

            string args = string.Format(
                "/create /tn \"{0}\" /tr \"{1}\" /sc minute /mo {2} /ru SYSTEM /rl HIGHEST /f",
                TaskName, tr.Replace("\"", "\\\""), IntervalMinutes);

            int code;
            string output = RunSchtasks(args, out code);
            if (code != 0)
                throw new InvalidOperationException("schtasks נכשל (קוד " + code + "): " + output);

            Storage.Log(string.Format("ההרצה האוטומטית הותקנה (כל {0} דקות, חשבון SYSTEM). נתיב: {1}",
                                      IntervalMinutes, ExePath), "פעולה");
        }

        public static void Uninstall()
        {
            if (!Storage.IsElevated())
                throw new InvalidOperationException("הסרת ההרצה האוטומטית דורשת הרשאות מנהל.");

            int code;
            string output = RunSchtasks(string.Format("/delete /tn \"{0}\" /f", TaskName), out code);
            // קוד שונה מאפס כשהמשימה כבר לא קיימת — לא שגיאה אמיתית
            if (code != 0 && output.IndexOf("cannot find", StringComparison.OrdinalIgnoreCase) < 0
                          && output.IndexOf("לא ניתן למצוא", StringComparison.OrdinalIgnoreCase) < 0)
                throw new InvalidOperationException("schtasks נכשל (קוד " + code + "): " + output);

            Storage.Log("ההרצה האוטומטית הוסרה.", "פעולה");
        }

        // זיהוי קיום המשימה — גם בלי הרשאות מנהל.
        //
        // זו מלכודת אמיתית: משימה שרצה תחת SYSTEM אינה נראית למשתמש רגיל.
        // schtasks /query מחזיר Access denied, וממשק ה-COM זורק חריגה —
        // אבל שתי החריגות שונות זו מזו, וזה מה שמאפשר להבדיל:
        //     0x80070005 "אין הרשאה"  => המשימה קיימת, רק חסומה לקריאה
        //     0x80070002 "לא נמצא"    => המשימה באמת אינה קיימת
        // (אומת 24/11/2026. אין להסתמך על מפתח הרישום של TaskCache\Tree —
        //  בדיקת קיום שם מחזירה "קיים" לכל שם, גם מומצא.)
        public static TaskState GetState()
        {
            var st = new TaskState();
            object svc = null;
            try
            {
                Type t = Type.GetTypeFromProgID("Schedule.Service");
                if (t == null) { st.Error = "מתזמן המשימות אינו זמין במחשב הזה."; return st; }

                svc = Activator.CreateInstance(t);
                Invoke(svc, "Connect", new object[] { Type.Missing, Type.Missing, Type.Missing, Type.Missing });
                object folder = Invoke(svc, "GetFolder", new object[] { "\\" });
                try
                {
                    Invoke(folder, "GetTask", new object[] { TaskName });
                    st.Installed = true;
                    st.DetailsReadable = true;
                }
                catch (Exception ex)
                {
                    int hr = HResultOf(ex);
                    if (hr == unchecked((int)0x80070005))      // אין הרשאה => קיימת
                    {
                        st.Installed = true;
                        st.DetailsReadable = false;
                    }
                    else st.Installed = false;                  // 0x80070002 וכל השאר
                }
            }
            catch (Exception ex)
            {
                st.Error = ex.Message;
            }
            finally
            {
                if (svc != null) { try { Marshal.ReleaseComObject(svc); } catch { } }
            }
            return st;
        }

        private static int HResultOf(Exception ex)
        {
            Exception e = ex;
            while (e.InnerException != null) e = e.InnerException;
            return Marshal.GetHRForException(e);
        }

        private static object Invoke(object target, string method, object[] args)
        {
            return target.GetType().InvokeMember(method,
                System.Reflection.BindingFlags.InvokeMethod, null, target, args);
        }

        private static string RunSchtasks(string arguments, out int exitCode)
        {
            var psi = new ProcessStartInfo("schtasks.exe", arguments)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.Default,
                StandardErrorEncoding = Encoding.Default
            };
            using (Process p = Process.Start(psi))
            {
                string o = p.StandardOutput.ReadToEnd();
                string e = p.StandardError.ReadToEnd();
                p.WaitForExit(30000);
                exitCode = p.ExitCode;
                return (o + " " + e).Trim();
            }
        }
    }
}
