// Storage.cs — הגדרות, מצב, יומן ודיווח ריצה.
//
// הכל יושב ב-%ProgramData%\PrintQueueCleaner ולא לצד ה-exe, משתי סיבות:
// הסריקה רצה תחת SYSTEM וחייבת מקום שהיא יכולה לכתוב בו, ו-exe שהונח
// ב-Program Files או בשולחן העבודה של משתמש אחר לא תמיד ניתן לכתיבה.
//
// הפורמט הוא שורות key=value פשוטות ולא JSON, כדי שאפשר יהיה לפתוח
// את הקובץ בפנקס רשימות ולתקן ביד בלי כלים.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace PrintQueueCleaner
{
    internal sealed class Settings
    {
        public bool Enabled = true;
        public bool DryRun = false;
        public List<string> Printers = new List<string>();   // ריק = כל המדפסות
        public int MinutesNoProgress = 5;
        public int ErrorGraceMinutes = 1;
        public bool DeleteOnError = true;
        public bool DeletePaperOut = false;
        public bool DeletePaused = false;
        // עבודה שכבר התחילה לעבור למדפסת (מצב Printing) — חלק ממנה כבר
        // בזיכרון המכונה. כבוי כברירת מחדל, כי זה גם המצב של רוב
        // העבודות התקועות באמת.
        public bool SkipJobsAtPrinter = false;
        public bool DeletePrintedLeftovers = true;
        public int PrintedLeftoverMinutes = 10;
        public bool SpoolerResetEnabled = true;
        public int SpoolerResetAfterAttempts = 3;
        public int LogKeepDays = 60;
    }

    internal static class Storage
    {
        private static string _dataDir;

        public static bool DataDirWasOverridden { get; private set; }

        public static string DataDir
        {
            get
            {
                if (_dataDir == null)
                {
                    _dataDir = Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                        "PrintQueueCleaner");
                }
                return _dataDir;
            }
            set { _dataDir = value; DataDirWasOverridden = true; }
        }

        public static string LogDir { get { return Path.Combine(DataDir, "logs"); } }
        private static string SettingsPath { get { return Path.Combine(DataDir, "settings.ini"); } }
        private static string StatePath { get { return Path.Combine(DataDir, "state.txt"); } }
        private static string StatusPath { get { return Path.Combine(DataDir, "last-run.ini"); } }

        public static void EnsureFolders()
        {
            Directory.CreateDirectory(DataDir);
            Directory.CreateDirectory(LogDir);
        }

        // ---------- כתיבה אטומית ----------
        // הקידוד נעשה לפני שנוגעים בקובץ היעד, וההחלפה היא שינוי-שם
        // באותו כונן. כך כשל באמצע לא משאיר קובץ באפס בתים.
        private static void WriteAtomic(string path, string text)
        {
            EnsureFolders();
            string tmp = path + ".tmp";
            File.WriteAllText(tmp, text, new UTF8Encoding(false));
            if (File.Exists(path)) File.Replace(tmp, path, null);
            else File.Move(tmp, path);
        }

        // ---------- הגדרות ----------

        public static Settings LoadSettings()
        {
            var s = new Settings();
            if (!File.Exists(SettingsPath)) { SaveSettings(s); return s; }

            // מפתחות שנמצאו בקובץ. אם גרסה חדשה הוסיפה הגדרה שאינה שם,
            // הקובץ נכתב מחדש בסוף — אחרת מי שפותח אותו לא רואה אותה בכלל.
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            try
            {
                foreach (string raw in File.ReadAllLines(SettingsPath, Encoding.UTF8))
                {
                    string line = raw.Trim();
                    if (line.Length == 0 || line.StartsWith("#")) continue;
                    int eq = line.IndexOf('=');
                    if (eq <= 0) continue;
                    string k = line.Substring(0, eq).Trim();
                    string v = line.Substring(eq + 1).Trim();
                    seen.Add(k);

                    switch (k)
                    {
                        case "enabled": s.Enabled = ParseBool(v, s.Enabled); break;
                        case "dryRun": s.DryRun = ParseBool(v, s.DryRun); break;
                        case "printers":
                            s.Printers.Clear();
                            if (v.Length > 0)
                                foreach (string p in v.Split('|'))
                                    if (p.Trim().Length > 0) s.Printers.Add(p.Trim());
                            break;
                        case "minutesNoProgress": s.MinutesNoProgress = ParseInt(v, s.MinutesNoProgress); break;
                        case "errorGraceMinutes": s.ErrorGraceMinutes = ParseInt(v, s.ErrorGraceMinutes); break;
                        case "deleteOnError": s.DeleteOnError = ParseBool(v, s.DeleteOnError); break;
                        case "deletePaperOut": s.DeletePaperOut = ParseBool(v, s.DeletePaperOut); break;
                        case "deletePaused": s.DeletePaused = ParseBool(v, s.DeletePaused); break;
                        case "skipJobsAtPrinter": s.SkipJobsAtPrinter = ParseBool(v, s.SkipJobsAtPrinter); break;
                        case "deletePrintedLeftovers": s.DeletePrintedLeftovers = ParseBool(v, s.DeletePrintedLeftovers); break;
                        case "printedLeftoverMinutes": s.PrintedLeftoverMinutes = ParseInt(v, s.PrintedLeftoverMinutes); break;
                        case "spoolerResetEnabled": s.SpoolerResetEnabled = ParseBool(v, s.SpoolerResetEnabled); break;
                        case "spoolerResetAfterAttempts": s.SpoolerResetAfterAttempts = ParseInt(v, s.SpoolerResetAfterAttempts); break;
                        case "logKeepDays": s.LogKeepDays = ParseInt(v, s.LogKeepDays); break;
                    }
                }
            }
            catch (Exception ex)
            {
                Log("קובץ ההגדרות פגום — חוזר לברירות המחדל. " + ex.Message, "שגיאה");
                return new Settings();
            }

            foreach (string k in KnownKeys)
            {
                if (!seen.Contains(k)) { SaveSettings(s); break; }
            }
            return s;
        }

        private static readonly string[] KnownKeys = {
            "enabled", "dryRun", "printers", "minutesNoProgress", "errorGraceMinutes",
            "deleteOnError", "deletePaperOut", "deletePaused", "skipJobsAtPrinter",
            "deletePrintedLeftovers", "printedLeftoverMinutes",
            "spoolerResetEnabled", "spoolerResetAfterAttempts", "logKeepDays"
        };

        public static void SaveSettings(Settings s)
        {
            var sb = new StringBuilder();
            sb.AppendLine("# הגדרות איפוס תור הדפסות. אפשר לערוך כאן ביד, או מהחלון.");
            sb.AppendLine("# שורה שמתחילה ב-# היא הערה. השמירה מהחלון דורסת את הקובץ.");
            sb.AppendLine();
            sb.AppendLine("# האם המערכת פעילה בכלל (0 עוצר הכל בלי להסיר את ההרצה האוטומטית)");
            sb.AppendLine("enabled=" + B(s.Enabled));
            sb.AppendLine("# מצב בדיקה: רושם ביומן מה היה נמחק, בלי למחוק באמת");
            sb.AppendLine("dryRun=" + B(s.DryRun));
            sb.AppendLine("# שמות המדפסות שבטיפול, מופרדים בקו אנכי. שורה ריקה = כל המדפסות");
            sb.AppendLine("printers=" + string.Join("|", s.Printers.ToArray()));
            sb.AppendLine("# עבודה שלא הדפיסה עוד עמוד יותר מכך — נמחקת");
            sb.AppendLine("minutesNoProgress=" + s.MinutesNoProgress);
            sb.AppendLine("# זמן חסד לפני מחיקת עבודה בשגיאה, כדי לא להרוג תקלה רגעית");
            sb.AppendLine("errorGraceMinutes=" + s.ErrorGraceMinutes);
            sb.AppendLine("deleteOnError=" + B(s.DeleteOnError));
            sb.AppendLine("# ממתינה לנייר / להתערבות — כברירת מחדל לא נוגעים");
            sb.AppendLine("deletePaperOut=" + B(s.DeletePaperOut));
            sb.AppendLine("# עבודה שמישהו השהה בכוונה — כברירת מחדל לא נוגעים");
            sb.AppendLine("deletePaused=" + B(s.DeletePaused));
            sb.AppendLine("# עבודה שכבר התחילה לעבור למדפסת — 1 = לא לגעת בה אף פעם");
            sb.AppendLine("skipJobsAtPrinter=" + B(s.SkipJobsAtPrinter));
            sb.AppendLine("# עבודות שכבר הודפסו ונשארו תקועות בתור");
            sb.AppendLine("deletePrintedLeftovers=" + B(s.DeletePrintedLeftovers));
            sb.AppendLine("printedLeftoverMinutes=" + s.PrintedLeftoverMinutes);
            sb.AppendLine("# עבודה שמסרבת להימחק — איפוס שירות ההדפסה כמוצא אחרון");
            sb.AppendLine("spoolerResetEnabled=" + B(s.SpoolerResetEnabled));
            sb.AppendLine("spoolerResetAfterAttempts=" + s.SpoolerResetAfterAttempts);
            sb.AppendLine("logKeepDays=" + s.LogKeepDays);
            WriteAtomic(SettingsPath, sb.ToString());
        }

        private static string B(bool b) { return b ? "1" : "0"; }

        private static bool ParseBool(string v, bool fallback)
        {
            if (v == "1" || v.Equals("true", StringComparison.OrdinalIgnoreCase)) return true;
            if (v == "0" || v.Equals("false", StringComparison.OrdinalIgnoreCase)) return false;
            return fallback;
        }

        private static int ParseInt(string v, int fallback)
        {
            int n;
            return int.TryParse(v, NumberStyles.Integer, CultureInfo.InvariantCulture, out n) ? n : fallback;
        }

        // ---------- מצב (מעקב התקדמות בין סריקות) ----------
        // שורה לכל עבודה: key|firstSeenTicks|lastProgressTicks|pages|size|attempts
        // ה-key עצמו מכיל קו אנכי, ולכן הפיצול הוא מהסוף.

        public static Dictionary<string, JobMemory> LoadState()
        {
            var d = new Dictionary<string, JobMemory>();
            if (!File.Exists(StatePath)) return d;
            try
            {
                foreach (string line in File.ReadAllLines(StatePath, Encoding.UTF8))
                {
                    if (line.Trim().Length == 0) continue;
                    string[] p = line.Split('|');
                    if (p.Length < 6) continue;
                    int n = p.Length;
                    string key = string.Join("|", p, 0, n - 5);
                    d[key] = new JobMemory
                    {
                        FirstSeen = new DateTime(long.Parse(p[n - 5], CultureInfo.InvariantCulture)),
                        LastProgressAt = new DateTime(long.Parse(p[n - 4], CultureInfo.InvariantCulture)),
                        Pages = uint.Parse(p[n - 3], CultureInfo.InvariantCulture),
                        Size = uint.Parse(p[n - 2], CultureInfo.InvariantCulture),
                        Attempts = int.Parse(p[n - 1], CultureInfo.InvariantCulture)
                    };
                }
            }
            catch { return new Dictionary<string, JobMemory>(); }
            return d;
        }

        public static void SaveState(Dictionary<string, JobMemory> state)
        {
            var sb = new StringBuilder();
            foreach (var kv in state)
            {
                sb.AppendLine(string.Join("|", new string[] {
                    kv.Key,
                    kv.Value.FirstSeen.Ticks.ToString(CultureInfo.InvariantCulture),
                    kv.Value.LastProgressAt.Ticks.ToString(CultureInfo.InvariantCulture),
                    kv.Value.Pages.ToString(CultureInfo.InvariantCulture),
                    kv.Value.Size.ToString(CultureInfo.InvariantCulture),
                    kv.Value.Attempts.ToString(CultureInfo.InvariantCulture)
                }));
            }
            WriteAtomic(StatePath, sb.ToString());
        }

        // ---------- יומן ----------

        public static void Log(string message, string level)
        {
            try
            {
                EnsureFolders();
                string line = string.Format("{0}  [{1}]  {2}",
                    DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss", CultureInfo.InvariantCulture), level, message);
                string file = Path.Combine(LogDir, "queue-" + DateTime.Now.ToString("yyyy-MM") + ".log");
                // שתי ריצות יכולות להיפגש; לא מפילים את הסריקה בגלל היומן
                for (int i = 0; i < 5; i++)
                {
                    try
                    {
                        using (var sw = new StreamWriter(file, true, new UTF8Encoding(false)))
                            sw.WriteLine(line);
                        return;
                    }
                    catch { System.Threading.Thread.Sleep(120); }
                }
            }
            catch { /* היומן לא מפיל את התוכנה */ }
        }

        public static string[] LogTail(int lines)
        {
            try
            {
                if (!Directory.Exists(LogDir)) return new string[0];
                var files = new List<string>(Directory.GetFiles(LogDir, "queue-*.log"));
                if (files.Count == 0) return new string[0];
                files.Sort();
                string newest = files[files.Count - 1];
                string[] all = File.ReadAllLines(newest, Encoding.UTF8);
                int take = Math.Min(lines, all.Length);
                var res = new string[take];
                Array.Copy(all, all.Length - take, res, 0, take);
                return res;
            }
            catch { return new string[0]; }
        }

        public static string CurrentLogFile()
        {
            return Path.Combine(LogDir, "queue-" + DateTime.Now.ToString("yyyy-MM") + ".log");
        }

        public static void PurgeOldLogs(int keepDays)
        {
            try
            {
                if (!Directory.Exists(LogDir)) return;
                DateTime cutoff = DateTime.Now.AddDays(-Math.Abs(keepDays));
                foreach (string f in Directory.GetFiles(LogDir, "queue-*.log"))
                    if (File.GetLastWriteTime(f) < cutoff) { try { File.Delete(f); } catch { } }
            }
            catch { }
        }

        // ---------- דיווח ריצה אחרונה ----------

        public sealed class RunStatus
        {
            public DateTime Time;
            public int Scanned, Deleted, Failed;
            public bool DryRun, SpoolerReset, Elevated;
            public bool Valid;
        }

        public static void SaveRunStatus(RunStatus r)
        {
            var sb = new StringBuilder();
            sb.AppendLine("time=" + r.Time.ToString("o", CultureInfo.InvariantCulture));
            sb.AppendLine("scanned=" + r.Scanned);
            sb.AppendLine("deleted=" + r.Deleted);
            sb.AppendLine("failed=" + r.Failed);
            sb.AppendLine("dryRun=" + (r.DryRun ? "1" : "0"));
            sb.AppendLine("spoolerReset=" + (r.SpoolerReset ? "1" : "0"));
            sb.AppendLine("elevated=" + (r.Elevated ? "1" : "0"));
            WriteAtomic(StatusPath, sb.ToString());
        }

        public static RunStatus LoadRunStatus()
        {
            var r = new RunStatus { Valid = false };
            if (!File.Exists(StatusPath)) return r;
            try
            {
                foreach (string line in File.ReadAllLines(StatusPath, Encoding.UTF8))
                {
                    int eq = line.IndexOf('=');
                    if (eq <= 0) continue;
                    string k = line.Substring(0, eq), v = line.Substring(eq + 1);
                    switch (k)
                    {
                        case "time": r.Time = DateTime.Parse(v, CultureInfo.InvariantCulture,
                                         DateTimeStyles.RoundtripKind); break;
                        case "scanned": r.Scanned = ParseInt(v, 0); break;
                        case "deleted": r.Deleted = ParseInt(v, 0); break;
                        case "failed": r.Failed = ParseInt(v, 0); break;
                        case "dryRun": r.DryRun = ParseBool(v, false); break;
                        case "spoolerReset": r.SpoolerReset = ParseBool(v, false); break;
                        case "elevated": r.Elevated = ParseBool(v, false); break;
                    }
                }
                r.Valid = true;
            }
            catch { r.Valid = false; }
            return r;
        }

        public static bool IsElevated()
        {
            try
            {
                using (var id = System.Security.Principal.WindowsIdentity.GetCurrent())
                    return new System.Security.Principal.WindowsPrincipal(id)
                        .IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
            }
            catch { return false; }
        }
    }
}
