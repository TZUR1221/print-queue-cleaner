// Engine.cs — ההחלטה מי "תקוע". קוד טהור: לא קורא למדפסות ולא כותב לדיסק,
// ולכן אפשר לבדוק אותו במלואו (ראה SelfTest.cs).
//
// הרעיון המרכזי: בכל סריקה נשמר מונה העמודים של כל עבודה. עלה המונה —
// העבודה מתקדמת ושעון חוסר-ההתקדמות מתאפס. לכן עבודה של 500 עמודים
// שרצה חצי שעה לא נמחקת לעולם, כל זמן שהיא ממשיכה להדפיס.

using System;
using System.Collections.Generic;

namespace PrintQueueCleaner
{
    internal sealed class JobMemory
    {
        public DateTime FirstSeen;
        public DateTime LastProgressAt;
        public uint Pages;
        public uint Size;
        public int Attempts;
    }

    internal sealed class Decision
    {
        public PrintJobInfo Job;
        public bool Delete;
        public string Reason;
        public double IdleMinutes;
        public double AgeMinutes;
        public bool Progressed;
        public bool IsMoving;
        public int Attempts;

        public string Label
        {
            get
            {
                return string.Format("'{0}' (מדפסת: {1}, מזהה: {2}, משתמש: {3})",
                                     Job.Document, Job.PrinterName, Job.JobId, Job.UserName);
            }
        }
    }

    internal sealed class ScanResult
    {
        public List<Decision> Decisions = new List<Decision>();
        public Dictionary<string, JobMemory> NewState = new Dictionary<string, JobMemory>();
    }

    internal static class Engine
    {
        public static ScanResult Decide(List<PrintJobInfo> jobs,
                                        Dictionary<string, JobMemory> previous,
                                        DateTime now,
                                        Settings s)
        {
            if (previous == null) previous = new Dictionary<string, JobMemory>();
            var result = new ScanResult();

            foreach (var job in jobs)
            {
                string key = job.Key;
                DateTime firstSeen, lastProgress;
                int attempts = 0;
                bool progressed;

                JobMemory prev;
                if (previous.TryGetValue(key, out prev))
                {
                    firstSeen = prev.FirstSeen;
                    lastProgress = prev.LastProgressAt;
                    attempts = prev.Attempts;
                    progressed = job.PagesPrinted != prev.Pages || job.Size != prev.Size;
                    if (progressed) lastProgress = now;
                }
                else
                {
                    // בפעם הראשונה שאנחנו רואים עבודה אין דרך לדעת אם היא מתקדמת.
                    // FirstSeen לפי זמן השליחה (לחישוב שגיאות), אבל שעון
                    // ההתקדמות מתחיל עכשיו — כדי לא להרוג עבודה ארוכה שבאמת מדפיסה.
                    firstSeen = job.Submitted < now ? job.Submitted : now;
                    lastProgress = now;
                    progressed = true;
                }

                double ageMinutes = Math.Round((now - firstSeen).TotalMinutes, 2);
                double idleMinutes = Math.Round((now - lastProgress).TotalMinutes, 2);
                bool isMoving = Has(job, JobStatus.Printing) || Has(job, JobStatus.Spooling);

                bool del = false;
                string reason;

                if (Has(job, JobStatus.Deleting))
                {
                    // "בתהליך מחיקה" שנתקע הוא המקרה הקלאסי שחוסם את כל התור
                    if (ageMinutes >= s.ErrorGraceMinutes)
                    {
                        del = true;
                        reason = string.Format("תקועה במחיקה {0} דק'", ageMinutes);
                    }
                    else reason = "בתהליך מחיקה — ממתין";
                }
                else if (s.SkipJobsAtPrinter && Has(job, JobStatus.Printing))
                {
                    // מצב Printing פירושו שהנתונים כבר זורמים אל המכונה, ולכן
                    // חלק מהעבודה כבר בזיכרון שלה. מחיקה כאן משאירה את המכונה
                    // עם חצי עבודה. בא אחרי הבדיקה של Deleting, כי עבודה שכבר
                    // ביקשו לבטל היא בדיוק זו שחוסמת את התור.
                    reason = "כבר עוברת למדפסת — לא נוגעים (לפי ההגדרה)";
                }
                else if (Has(job, JobStatus.Error) || Has(job, JobStatus.Offline) || Has(job, JobStatus.BlockedDevQ))
                {
                    if (!s.DeleteOnError) reason = "שגיאה — מחיקה כבויה בהגדרות";
                    else if (ageMinutes >= s.ErrorGraceMinutes)
                    {
                        del = true;
                        reason = string.Format("{0} — {1} דק'", job.StatusText, ageMinutes);
                    }
                    else reason = "שגיאה — בזמן חסד";
                }
                else if (Has(job, JobStatus.PaperOut) || Has(job, JobStatus.UserIntervention))
                {
                    if (s.DeletePaperOut && ageMinutes >= s.ErrorGraceMinutes)
                    {
                        del = true;
                        reason = string.Format("{0} — {1} דק'", job.StatusText, ageMinutes);
                    }
                    else reason = "ממתינה לנייר או להתערבות — לא נוגעים";
                }
                else if (Has(job, JobStatus.Paused))
                {
                    if (s.DeletePaused && idleMinutes >= s.MinutesNoProgress)
                    {
                        del = true;
                        reason = string.Format("מושהית {0} דק'", idleMinutes);
                    }
                    else reason = "מושהית ביודעין — לא נוגעים";
                }
                else if (!isMoving && (Has(job, JobStatus.Printed) || Has(job, JobStatus.Complete) || Has(job, JobStatus.Retained)))
                {
                    if (s.DeletePrintedLeftovers && idleMinutes >= s.PrintedLeftoverMinutes)
                    {
                        del = true;
                        reason = string.Format("הודפסה ונותרה בתור {0} דק'", idleMinutes);
                    }
                    else reason = "הודפסה — ממתין לפני ניקוי";
                }
                else
                {
                    if (idleMinutes >= s.MinutesNoProgress)
                    {
                        del = true;
                        reason = string.Format("ללא התקדמות {0} דק' (עמודים: {1})", idleMinutes, job.PagesPrinted);
                    }
                    else reason = string.Format("מתקדמת כרגע (עמודים: {0})", job.PagesPrinted);
                }

                result.Decisions.Add(new Decision
                {
                    Job = job, Delete = del, Reason = reason,
                    IdleMinutes = idleMinutes, AgeMinutes = ageMinutes,
                    Progressed = progressed, IsMoving = isMoving, Attempts = attempts
                });

                result.NewState[key] = new JobMemory
                {
                    FirstSeen = firstSeen,
                    LastProgressAt = lastProgress,
                    Pages = job.PagesPrinted,
                    Size = job.Size,
                    Attempts = attempts
                };
            }

            return result;
        }

        private static bool Has(PrintJobInfo job, JobStatus flag)
        {
            return (job.Status & flag) != 0;
        }

        // האם מותר לאפס את שירות ההדפסה כרגע? רק אם אין עבודה אחרת שבאמת זזה —
        // אחרת האיפוס היה הורג הדפסה תקינה של מישהו אחר באותו רגע.
        public static bool SpoolerResetAllowed(List<Decision> decisions, HashSet<string> failedKeys)
        {
            foreach (var d in decisions)
            {
                if (failedKeys.Contains(d.Job.Key)) continue;
                if (d.IsMoving && d.Progressed) return false;
            }
            return true;
        }
    }
}
