// SelfTest.cs — הבדיקות נוסעות בתוך ה-exe עצמו.
//
// למה בפנים ולא בקובץ נפרד: ה-exe מופץ לאנשים אחרים, ואני רוצה
// שמי שמקבל אותו יוכל להוכיח לעצמו שהוא עובד על המחשב שלו —
// PrintQueueCleaner.exe --selftest
//
// שני חלקים: בדיקות המנוע (קוד טהור, בלי לגעת במדפסות) ובדיקת אמת
// שיוצרת עבודת הדפסה תקועה ומוודאת שהיא נמחקת. בדיקת האמת אינה
// מדפיסה שום נייר — העבודה מושהית לפני שהמדפסת מקבלת אותה.

using System;
using System.Collections.Generic;
using System.Threading;

namespace PrintQueueCleaner
{
    internal static class SelfTest
    {
        private static int _pass, _fail;
        private static readonly DateTime Now = new DateTime(2026, 11, 24, 10, 0, 0);

        public static int Run(string[] args)
        {
            _pass = 0; _fail = 0;
            // הקידוד נקבע ב-Program.EnsureConsole. אין לגעת בו כאן:
            // Console.OutputEncoding זורק "The handle is invalid" כשהפלט
            // מופנה לקובץ ואין קונסולה אמיתית.

            Console.WriteLine();
            Console.WriteLine("בדיקות איפוס תור הדפסות");
            Console.WriteLine("------------------------");
            EngineTests();

            bool skipLive = Array.IndexOf(args, "--no-live") >= 0;
            if (!skipLive)
            {
                Console.WriteLine();
                Console.WriteLine("בדיקת אמת מול תור הדפסה אמיתי");
                Console.WriteLine("------------------------------");
                LiveTest();
            }

            Console.WriteLine("------------------------");
            Console.WriteLine(string.Format("סה\"כ: {0} עוברות, {1} נכשלות", _pass, _fail));
            Console.WriteLine();
            return _fail == 0 ? 0 : 1;
        }

        private static void Check(string name, bool ok, string detail)
        {
            if (ok) { _pass++; Console.WriteLine("  עובר   " + name); }
            else
            {
                _fail++;
                Console.WriteLine("  נכשל   " + name + (string.IsNullOrEmpty(detail) ? "" : "  " + detail));
            }
        }

        // ---------- בדיקות המנוע ----------

        private static Settings Def() { return new Settings(); }

        private static PrintJobInfo Job(JobStatus status, uint pages, DateTime submitted)
        {
            return new PrintJobInfo
            {
                PrinterName = "תת שחור לבן", JobId = 1, Document = "מבחן בחומש.pdf",
                UserName = "מורה", Status = status, PagesPrinted = pages,
                Size = 1000, TotalPages = 10, Submitted = submitted
            };
        }

        private static Dictionary<string, JobMemory> Mem(PrintJobInfo j, double seenAgo, double progressAgo,
                                                         uint pages, int attempts)
        {
            var d = new Dictionary<string, JobMemory>();
            d[j.Key] = new JobMemory
            {
                FirstSeen = Now.AddMinutes(-seenAgo),
                LastProgressAt = Now.AddMinutes(-progressAgo),
                Pages = pages, Size = 1000, Attempts = attempts
            };
            return d;
        }

        private static void Expect(string name, PrintJobInfo j, Dictionary<string, JobMemory> prev,
                                   bool shouldDelete, Settings s)
        {
            var r = Engine.Decide(new List<PrintJobInfo> { j }, prev, Now, s ?? Def());
            Decision d = r.Decisions[0];
            Check(name, d.Delete == shouldDelete,
                  string.Format("(צפוי {0}, קיבלנו {1}; סיבה: {2})",
                                shouldDelete ? "מחיקה" : "השארה",
                                d.Delete ? "מחיקה" : "השארה", d.Reason));
        }

        private static void EngineTests()
        {
            PrintJobInfo j;

            // 1. עבודה שנראית בפעם הראשונה לא נמחקת מיד, גם אם נשלחה מזמן
            j = Job(JobStatus.Printing, 0, Now.AddHours(-3));
            Expect("עבודה חדשה לנו, אפילו ישנה — לא נמחקת בסריקה הראשונה",
                   j, new Dictionary<string, JobMemory>(), false, null);

            // 2. מדפיסה ומתקדמת — נשארת
            j = Job(JobStatus.Printing, 42, Now);
            Expect("עבודה ארוכה שמתקדמת (17 עמודים ואז 42) — נשארת",
                   j, Mem(j, 30, 30, 17, 0), false, null);

            // 3. עומדת 10 דקות בלי להתקדם — נמחקת
            j = Job(JobStatus.Printing, 3, Now);
            Expect("עבודה שלא זזה 10 דקות — נמחקת", j, Mem(j, 10, 10, 3, 0), true, null);

            // 4. עומדת 3 דקות — הסף 5, נשארת
            j = Job(JobStatus.Printing, 3, Now);
            Expect("עבודה שלא זזה 3 דקות (סף 5) — נשארת", j, Mem(j, 3, 3, 3, 0), false, null);

            // 5. שגיאה אחרי זמן החסד
            j = Job(JobStatus.Error, 0, Now.AddMinutes(-5));
            Expect("עבודה בשגיאה 5 דקות — נמחקת", j, Mem(j, 5, 5, 0, 0), true, null);

            // 6. שגיאה בת 20 שניות — בזמן חסד
            j = Job(JobStatus.Error, 0, Now.AddSeconds(-20));
            Expect("עבודה בשגיאה 20 שניות — בזמן חסד, נשארת", j, Mem(j, 0.33, 0.33, 0, 0), false, null);

            // 7. מדפסת לא מחוברת
            j = Job(JobStatus.Offline, 0, Now.AddMinutes(-4));
            Expect("מדפסת לא מחוברת — נמחקת", j, Mem(j, 4, 4, 0, 0), true, null);

            // 8. כיבוי מחיקת שגיאות בהגדרות
            var s8 = Def(); s8.DeleteOnError = false;
            j = Job(JobStatus.Error, 0, Now.AddHours(-1));
            Expect("שגיאה כשהמחיקה כבויה בהגדרות — נשארת", j, Mem(j, 60, 60, 0, 0), false, s8);

            // 9. חסר נייר — ברירת מחדל לא נוגעים
            j = Job(JobStatus.PaperOut, 0, Now.AddHours(-1));
            Expect("ממתינה לנייר — כברירת מחדל נשארת", j, Mem(j, 60, 60, 0, 0), false, null);

            // 10. חסר נייר כשהמתג דלוק
            var s10 = Def(); s10.DeletePaperOut = true;
            Expect("ממתינה לנייר כשהמתג דלוק — נמחקת", j, Mem(j, 60, 60, 0, 0), true, s10);

            // 11. מושהית בכוונה
            j = Job(JobStatus.Paused, 0, Now.AddHours(-1));
            Expect("עבודה מושהית — כברירת מחדל נשארת", j, Mem(j, 60, 60, 0, 0), false, null);

            // 12. מושהית כשהמתג דלוק
            var s12 = Def(); s12.DeletePaused = true;
            Expect("עבודה מושהית כשהמתג דלוק — נמחקת", j, Mem(j, 60, 60, 0, 0), true, s12);

            // 13. תקועה במחיקה — המקרה שחוסם את כל התור
            j = Job(JobStatus.Deleting, 0, Now.AddMinutes(-4));
            Expect("תקועה במחיקה 4 דקות — נמחקת שוב", j, Mem(j, 4, 4, 0, 0), true, null);

            // 14. הודפסה ונשארה בתור
            j = Job(JobStatus.Printed | JobStatus.Retained, 10, Now.AddMinutes(-20));
            Expect("הודפסה ונשארה בתור 20 דקות — מנוקה", j, Mem(j, 20, 20, 10, 0), true, null);

            // 15. שמורה אך עדיין מדפיסה ומתקדמת — זה המקרה שהורג הדפסה פעילה
            //     אם בודקים Retained לפני Printing
            j = Job(JobStatus.Printing | JobStatus.Retained, 55, Now.AddMinutes(-40));
            Expect("שמורה אך עדיין מדפיסה ומתקדמת — נשארת", j, Mem(j, 40, 40, 20, 0), false, null);

            // 16. המתג "לא לגעת בעבודה שכבר עוברת למדפסת" — כבוי כברירת מחדל,
            //     ולכן עבודה תקועה במצב Printing עדיין נמחקת
            j = Job(JobStatus.Printing, 3, Now);
            Expect("עבודה תקועה שעוברת למדפסת — נמחקת כשהמתג כבוי (ברירת מחדל)",
                   j, Mem(j, 30, 30, 3, 0), true, null);

            // 17. אותה עבודה בדיוק, כשהמתג דלוק — לא נוגעים
            var s17 = Def(); s17.SkipJobsAtPrinter = true;
            Expect("אותה עבודה כשהמתג דלוק — לא נוגעים",
                   j, Mem(j, 30, 30, 3, 0), false, s17);

            // 18. המתג אינו מגן על עבודה שעדיין לא התחילה לעבור (ממתינה בתור)
            j = Job(JobStatus.None, 0, Now);
            Expect("עבודה שעוד לא נשלחה למדפסת — נמחקת גם כשהמתג דלוק",
                   j, Mem(j, 30, 30, 0, 0), true, s17);

            // 19. והוא גם אינו מגן על עבודה שנתקעה ב"מבטל" — זו שחוסמת את התור
            j = Job(JobStatus.Printing | JobStatus.Deleting, 0, Now.AddMinutes(-10));
            Expect("תקועה במחיקה — נמחקת גם כשהמתג דלוק",
                   j, Mem(j, 10, 10, 0, 0), true, s17);

            // 20. איפוס ספולר נחסם כשעבודה אחרת מדפיסה בפועל
            var stuck = Job(JobStatus.Deleting, 0, Now.AddMinutes(-10));
            stuck.JobId = 7;
            var moving = Job(JobStatus.Printing, 30, Now.AddMinutes(-5));
            moving.JobId = 8; moving.PrinterName = "גנים שחור";
            var memMoving = Mem(moving, 5, 5, 10, 0);
            var r16 = Engine.Decide(new List<PrintJobInfo> { stuck, moving }, memMoving, Now, Def());
            var failed = new HashSet<string>(); failed.Add(stuck.Key);
            Check("איפוס ספולר נחסם כשיש הדפסה פעילה אחרת",
                  !Engine.SpoolerResetAllowed(r16.Decisions, failed), "");

            // 21. איפוס ספולר מותר כשאין שום דבר שזז
            var r17 = Engine.Decide(new List<PrintJobInfo> { stuck }, Mem(stuck, 10, 10, 0, 0), Now, Def());
            Check("איפוס ספולר מותר כשאין הדפסה פעילה",
                  Engine.SpoolerResetAllowed(r17.Decisions, failed), "");

            // 22. שעון ההתקדמות מתאפס כשנדפס עוד עמוד
            j = Job(JobStatus.Printing, 99, Now);
            var r18 = Engine.Decide(new List<PrintJobInfo> { j }, Mem(j, 20, 20, 50, 0), Now, Def());
            Check("שעון ההתקדמות מתאפס כשנדפס עוד עמוד",
                  r18.NewState[j.Key].LastProgressAt == Now, "");

            // 23. עבודה שנעלמה מהתור נעלמת גם מהמצב (לא מצטבר לנצח)
            var r19 = Engine.Decide(new List<PrintJobInfo>(), Mem(j, 10, 10, 0, 0), Now, Def());
            Check("מצב של עבודה שנעלמה מהתור נמחק", r19.NewState.Count == 0, "");

            // 24. זיהוי המשימה לא מזהה כזב על שם מומצא
            string realName = TaskInstaller.TaskName;
            TaskInstaller.TaskName = "PQC-NoSuchTask-" + Guid.NewGuid().ToString("N").Substring(0, 8);
            bool fakeFound = TaskInstaller.GetState().Installed;
            TaskInstaller.TaskName = realName;
            Check("זיהוי ההרצה האוטומטית לא מזהה כזב על שם מומצא", !fakeFound, "");
        }

        // ---------- בדיקת אמת ----------

        private static void LiveTest()
        {
            const string preferred = "Microsoft Print to PDF";
            List<string> printers = Spooler.InstalledPrinters();
            string target = printers.Contains(preferred) ? preferred : null;
            if (target == null)
            {
                Console.WriteLine("  מדולג   '" + preferred + "' אינה קיימת במחשב, ואין לבדוק על מדפסת אמיתית (נייר).");
                return;
            }

            uint jobId = 0;
            try
            {
                jobId = Spooler.CreatePausedTestJob(target, "בדיקת איפוס תור — אין להדפיס");
                Thread.Sleep(700);

                List<PrintJobInfo> jobs = Spooler.GetJobs(target);
                PrintJobInfo mine = null;
                foreach (var j in jobs) if (j.JobId == jobId) mine = j;

                Check("Windows מדווח על העבודה בתור", mine != null, "");
                if (mine == null) return;

                Console.WriteLine("     מצב: " + mine.StatusText + "  |  מסמך: '" + mine.Document + "'");
                Check("המצב שדווח הוא 'מושהית'", (mine.Status & JobStatus.Paused) != 0,
                      "(קיבלנו: " + mine.StatusText + ")");

                Spooler.DeleteResult r = Spooler.DeleteJob(target, jobId);
                Thread.Sleep(900);
                bool gone = true;
                foreach (var j in Spooler.GetJobs(target)) if (j.JobId == jobId) gone = false;

                Check("העבודה נמחקה מהתור בפועל", r.Ok && gone,
                      r.Ok ? "" : "(" + r.Error + ")");
                if (gone) jobId = 0;
            }
            catch (Exception ex)
            {
                Check("בדיקת האמת הושלמה בלי חריגה", false, "(" + ex.Message + ")");
            }
            finally
            {
                if (jobId != 0) { try { Spooler.DeleteJob(target, jobId); } catch { } }
            }
        }
    }
}
