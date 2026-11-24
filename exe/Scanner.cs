// Scanner.cs — סריקה אחת: קורא את התורים, מפעיל את המנוע, מוחק, רושם ביומן.
// זה מה שרץ כל 2 דקות (PrintQueueCleaner.exe --scan).

using System;
using System.Collections.Generic;
using System.IO;
using System.ServiceProcess;

namespace PrintQueueCleaner
{
    internal static class Scanner
    {
        public static string RunOnce(bool forceDryRun, Action<string> report)
        {
            if (report == null) report = delegate { };
            DateTime now = DateTime.Now;
            Settings s = Storage.LoadSettings();
            if (forceDryRun) s.DryRun = true;

            var status = new Storage.RunStatus
            {
                Time = now, DryRun = s.DryRun, Elevated = Storage.IsElevated()
            };

            if (!s.Enabled)
            {
                Storage.SaveRunStatus(status);
                string m = "המערכת מושבתת בהגדרות — לא בוצעה פעולה.";
                report(m);
                return m;
            }

            List<string> printers = TargetPrinters(s);
            var jobs = new List<PrintJobInfo>();
            foreach (string p in printers)
                jobs.AddRange(Spooler.GetJobs(p));

            status.Scanned = jobs.Count;

            if (jobs.Count == 0)
            {
                Storage.SaveState(new Dictionary<string, JobMemory>());
                Storage.SaveRunStatus(status);
                Storage.PurgeOldLogs(s.LogKeepDays);
                string m = string.Format("התור ריק בכל {0} המדפסות שבטיפול.", printers.Count);
                report(m);
                return m;
            }

            var prev = Storage.LoadState();
            ScanResult res = Engine.Decide(jobs, prev, now, s);
            var newState = res.NewState;
            var failed = new HashSet<string>();

            foreach (Decision d in res.Decisions)
            {
                if (!d.Delete) continue;

                if (s.DryRun)
                {
                    Storage.Log("[סימולציה] הייתי מוחק " + d.Label + " — " + d.Reason, "סימולציה");
                    report("[סימולציה] " + d.Label + " — " + d.Reason);
                    continue;
                }

                Spooler.DeleteResult r = Spooler.DeleteJob(d.Job.PrinterName, d.Job.JobId);
                if (r.Ok)
                {
                    Storage.Log("נמחקה עבודה תקועה: " + d.Label + " — " + d.Reason + " [" + r.Method + "]", "מחיקה");
                    report("נמחקה: " + d.Label);
                    status.Deleted++;
                    newState.Remove(d.Job.Key);
                }
                else
                {
                    failed.Add(d.Job.Key);
                    status.Failed++;
                    JobMemory mem;
                    int tries = 1;
                    if (newState.TryGetValue(d.Job.Key, out mem)) { mem.Attempts++; tries = mem.Attempts; }
                    Storage.Log(string.Format("מחיקה נכשלה (ניסיון {0}): {1} — {2}", tries, d.Label, r.Error), "אזהרה");
                    report("מחיקה נכשלה: " + d.Label);
                }
            }

            // עבודה עקשנית: אחרי כמה נסיונות כושלים מאפסים את שירות ההדפסה,
            // אבל רק אם אין באותו רגע עבודה אחרת שמדפיסה בפועל.
            var stubborn = new List<string>();
            foreach (string k in failed)
            {
                JobMemory mem;
                if (newState.TryGetValue(k, out mem) && mem.Attempts >= s.SpoolerResetAfterAttempts)
                    stubborn.Add(k);
            }

            if (stubborn.Count > 0)
            {
                if (!s.SpoolerResetEnabled)
                    Storage.Log(string.Format("יש {0} עבודות שמסרבות להימחק, ואיפוס שירות ההדפסה כבוי בהגדרות. נדרשת התערבות.", stubborn.Count), "אזהרה");
                else if (!Storage.IsElevated())
                    Storage.Log("נדרש איפוס שירות ההדפסה אך ההרצה אינה בהרשאות מנהל.", "אזהרה");
                else if (!Engine.SpoolerResetAllowed(res.Decisions, failed))
                    Storage.Log("נדרש איפוס שירות ההדפסה, אך יש כרגע עבודה אחרת שמדפיסה בפועל — נדחה לסריקה הבאה.", "אזהרה");
                else
                {
                    try
                    {
                        ResetSpooler();
                        status.SpoolerReset = true;
                        foreach (string k in stubborn) newState.Remove(k);
                    }
                    catch (Exception ex)
                    {
                        Storage.Log("איפוס שירות ההדפסה נכשל: " + ex.Message, "שגיאה");
                    }
                }
            }

            Storage.SaveState(newState);
            Storage.SaveRunStatus(status);
            Storage.PurgeOldLogs(s.LogKeepDays);

            int kept = res.Decisions.Count - CountDeletes(res.Decisions);
            string summary = string.Format("סריקה הושלמה: {0} עבודות בתור, נמחקו {1}, נותרו {2}.",
                                           jobs.Count, status.Deleted, kept);
            report(summary);
            if (status.Deleted > 0 || status.Failed > 0 || s.DryRun)
                Storage.Log(string.Format("סיכום סריקה: בתור {0}, נמחקו {1}, כשלו {2}.",
                                          jobs.Count, status.Deleted, status.Failed), "סיכום");
            return summary;
        }

        private static int CountDeletes(List<Decision> ds)
        {
            int n = 0;
            foreach (var d in ds) if (d.Delete) n++;
            return n;
        }

        public static List<string> TargetPrinters(Settings s)
        {
            List<string> all = Spooler.InstalledPrinters();
            if (s.Printers.Count == 0) return all;

            var hit = new List<string>();
            foreach (string w in s.Printers)
            {
                if (all.Contains(w)) hit.Add(w);
                else Storage.Log("המדפסת '" + w + "' מופיעה בהגדרות אך אינה קיימת במחשב — מדולגת", "אזהרה");
            }
            return hit;
        }

        // מוצא אחרון: עבודה שמסרבת להימחק משוחררת רק בעצירת שירות
        // ההדפסה ומחיקת קובצי התור מהדיסק.
        private static void ResetSpooler()
        {
            Storage.Log("מאפס את שירות ההדפסה (Spooler)", "פעולה");
            using (var sc = new ServiceController("Spooler"))
            {
                if (sc.Status != ServiceControllerStatus.Stopped)
                {
                    sc.Stop();
                    sc.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(30));
                }

                int removed = 0;
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                                          "spool\\PRINTERS");
                if (Directory.Exists(dir))
                {
                    foreach (string f in Directory.GetFiles(dir))
                    {
                        string ext = Path.GetExtension(f).ToLowerInvariant();
                        if (ext == ".shd" || ext == ".spl")
                        {
                            try { File.Delete(f); removed++; } catch { }
                        }
                    }
                }

                sc.Start();
                sc.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(30));
                Storage.Log(string.Format("שירות ההדפסה הופעל מחדש. נמחקו {0} קובצי תור מהדיסק.", removed), "פעולה");
            }
        }
    }
}
