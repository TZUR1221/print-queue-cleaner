// Program.cs — נקודת הכניסה. exe אחד, כמה מצבים:
//
//   PrintQueueCleaner.exe              חלון ההגדרות (ברירת מחדל)
//   PrintQueueCleaner.exe --scan       סריקה אחת בשקט — זה מה שרץ כל 2 דקות
//   PrintQueueCleaner.exe --scan --dry-run   סריקה שרושמת ביומן בלי למחוק
//   PrintQueueCleaner.exe --install    התקנת ההרצה האוטומטית
//   PrintQueueCleaner.exe --uninstall  הסרת ההרצה האוטומטית
//   PrintQueueCleaner.exe --status     מצב בשורת הפקודה
//   PrintQueueCleaner.exe --selftest   בדיקות (20 לוגיות + בדיקת אמת)
//   PrintQueueCleaner.exe --formcheck  בניית החלון בלי להציג אותו
//
// דגל פנימי לכל המצבים:  --data <תיקייה>   מפנה את ההגדרות והיומן למקום
// אחר, כדי שבדיקה לא תיגע בהתקנה החיה.

using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace PrintQueueCleaner
{
    internal static class Program
    {
        // ה-exe נבנה כ-winexe, כדי שלא יקפוץ חלון קונסולה שחור בכל סריקה
        // ברקע. המחיר: ברירת המחדל היא בלי קונסולה, ולכן Console.WriteLine
        // נעלם. לכן במצבי שורת הפקודה מתחברים לקונסולה של מי שהפעיל,
        // ואם אין כזו (הפעלה בלחיצה כפולה) פותחים אחת.
        [DllImport("kernel32.dll")]
        private static extern bool AttachConsole(int processId);
        [DllImport("kernel32.dll")]
        private static extern bool AllocConsole();
        [DllImport("kernel32.dll")]
        private static extern IntPtr GetStdHandle(int nStdHandle);
        private const int ATTACH_PARENT_PROCESS = -1;
        private const int STD_OUTPUT_HANDLE = -11;

        private static void EnsureConsole()
        {
            // שלושה מצבים שונים, וכל אחד דורש טיפול אחר:
            //
            // 1. הפלט מופנה לקובץ או לצינור (כך הבדיקות מריצות אותנו) —
            //    יש ידית תקינה. אסור לגעת ב-Console.OutputEncoding, כי בלי
            //    קונסולה אמיתית הוא זורק "The handle is invalid". במקום זה
            //    כופים UTF-8 על הזרם עצמו, אחרת העברית נכתבת ב-ANSI
            //    ויוצאת ג'יבריש בקובץ.
            // 2. הרצה מתוך חלון שורת פקודה — מתחברים לקונסולה של המפעיל.
            // 3. הפעלה בלחיצה כפולה — אין קונסולה בכלל, פותחים אחת.
            IntPtr h = GetStdHandle(STD_OUTPUT_HANDLE);
            bool redirected = h != IntPtr.Zero && h != new IntPtr(-1);

            if (!redirected)
            {
                if (!AttachConsole(ATTACH_PARENT_PROCESS)) AllocConsole();
                try { Console.OutputEncoding = System.Text.Encoding.UTF8; } catch { }
            }

            try
            {
                var utf8 = new System.Text.UTF8Encoding(false);
                var so = new System.IO.StreamWriter(Console.OpenStandardOutput(), utf8);
                so.AutoFlush = true;
                Console.SetOut(so);
                var se = new System.IO.StreamWriter(Console.OpenStandardError(), utf8);
                se.AutoFlush = true;
                Console.SetError(se);
            }
            catch { }
        }

        private static bool NeedsConsole(string mode)
        {
            return mode == "--selftest" || mode == "--status" || mode == "--formcheck"
                || mode == "--install" || mode == "--uninstall"
                || mode == "--help" || mode == "-h" || mode == "/?";
        }

        [STAThread]
        private static int Main(string[] args)
        {
            try
            {
                ApplyOverride(ref args, "--data", delegate(string v) { Storage.DataDir = v; });
                ApplyOverride(ref args, "--task", delegate(string v) { TaskInstaller.TaskName = v; });
            }
            catch (Exception ex) { return Fail(ex.Message); }

            string mode = FirstSwitch(args);
            if (NeedsConsole(mode) || (mode == "--scan" && Has(args, "--verbose"))) EnsureConsole();

            try
            {
                switch (mode)
                {
                    case "--scan":
                        bool dry = Has(args, "--dry-run");
                        bool quiet = Has(args, "--quiet") || !Has(args, "--verbose");
                        // הסיכום נכתב כבר דרך ה-callback כשיש --verbose,
                        // ולכן אין להדפיס שוב את הערך המוחזר.
                        Scanner.RunOnce(dry, quiet ? (Action<string>)null : Console.WriteLine);
                        return 0;

                    case "--install":
                        TaskInstaller.Install();
                        Console.WriteLine("ההרצה האוטומטית הותקנה (כל 2 דקות, חשבון SYSTEM).");
                        return 0;

                    case "--uninstall":
                        TaskInstaller.Uninstall();
                        Console.WriteLine("ההרצה האוטומטית הוסרה.");
                        return 0;

                    case "--status":
                        PrintStatus();
                        return 0;

                    case "--selftest":
                        return SelfTest.Run(args);

                    case "--formcheck":
                        Application.EnableVisualStyles();
                        return MainForm.SelfCheck();

                    case "--help":
                    case "-h":
                    case "/?":
                        PrintHelp();
                        return 0;

                    case null:
                        Application.EnableVisualStyles();
                        Application.SetCompatibleTextRenderingDefault(false);
                        Application.Run(new MainForm());
                        return 0;

                    default:
                        Console.WriteLine("מצב לא מוכר: " + mode);
                        PrintHelp();
                        return 2;
                }
            }
            catch (Exception ex)
            {
                return Fail(ex.Message);
            }
        }

        private static int Fail(string message)
        {
            Storage.Log("כשל בהרצה: " + message, "שגיאה");
            Console.Error.WriteLine("שגיאה: " + message);
            return 1;
        }

        private static bool Has(string[] args, string flag)
        {
            foreach (string a in args)
                if (string.Equals(a, flag, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        private static string FirstSwitch(string[] args)
        {
            foreach (string a in args)
            {
                if (!a.StartsWith("-") && !a.StartsWith("/")) continue;
                string l = a.ToLowerInvariant();
                if (l == "--dry-run" || l == "--quiet" || l == "--verbose" || l == "--no-live") continue;
                return l;
            }
            return null;
        }

        // דגלים בצורת "--שם <ערך>". אחרי העיבוד הם מוסרים מהמערך, כדי
        // שלא יבלבלו את זיהוי המצב.
        private static void ApplyOverride(ref string[] args, string flag, Action<string> apply)
        {
            for (int i = 0; i < args.Length; i++)
            {
                if (!string.Equals(args[i], flag, StringComparison.OrdinalIgnoreCase)) continue;
                if (i + 1 >= args.Length)
                    throw new ArgumentException("אחרי " + flag + " חייב לבוא ערך.");

                apply(args[i + 1]);
                var rest = new System.Collections.Generic.List<string>();
                for (int j = 0; j < args.Length; j++)
                    if (j != i && j != i + 1) rest.Add(args[j]);
                args = rest.ToArray();
                return;
            }
        }

        private static void PrintStatus()
        {
            TaskState ts = TaskInstaller.GetState();
            Console.WriteLine("תיקיית נתונים:      " + Storage.DataDir);
            Console.WriteLine("הרשאות מנהל:        " + (Storage.IsElevated() ? "כן" : "לא"));
            if (ts.Error != null)
                Console.WriteLine("הרצה אוטומטית:      לא ניתן לקרוא (" + ts.Error + ")");
            else if (ts.Installed)
                Console.WriteLine("הרצה אוטומטית:      מותקנת" +
                                  (ts.DetailsReadable ? "" : " (הפרטים דורשים הרשאות מנהל)"));
            else
                Console.WriteLine("הרצה אוטומטית:      לא מותקנת");

            Storage.RunStatus r = Storage.LoadRunStatus();
            if (r.Valid)
                Console.WriteLine(string.Format("סריקה אחרונה:       {0}  |  {1} בתור, נמחקו {2}, כשלו {3}  |  כ-SYSTEM: {4}",
                    r.Time.ToString("dd/MM/yyyy HH:mm:ss"), r.Scanned, r.Deleted, r.Failed, r.Elevated ? "כן" : "לא"));
            else
                Console.WriteLine("סריקה אחרונה:       עדיין לא בוצעה");

            Settings s = Storage.LoadSettings();
            Console.WriteLine("מדפסות שבטיפול:     " +
                (s.Printers.Count == 0 ? "כולן" : string.Join(", ", s.Printers.ToArray())));
            Console.WriteLine("סף חוסר התקדמות:    " + s.MinutesNoProgress + " דקות");
            Console.WriteLine("מצב בדיקה:          " + (s.DryRun ? "דלוק (לא מוחק באמת)" : "כבוי"));
        }

        private static void PrintHelp()
        {
            Console.WriteLine();
            Console.WriteLine("איפוס תור הדפסות");
            Console.WriteLine("=================");
            Console.WriteLine("בלי שום דגל          פותח את חלון ההגדרות");
            Console.WriteLine("  --scan             סריקה אחת (זה מה שרץ כל 2 דקות)");
            Console.WriteLine("  --scan --verbose   סריקה עם פלט למסך");
            Console.WriteLine("  --scan --dry-run   סריקה שרושמת ביומן בלי למחוק");
            Console.WriteLine("  --install          התקנת ההרצה האוטומטית (דורש הרשאות מנהל)");
            Console.WriteLine("  --uninstall        הסרת ההרצה האוטומטית");
            Console.WriteLine("  --status           מה מצב המערכת");
            Console.WriteLine("  --selftest         בדיקות. --no-live מדלג על בדיקת האמת");
            Console.WriteLine();
            Console.WriteLine("דגלים לכל המצבים:");
            Console.WriteLine("  --data <תיקייה>    הגדרות ויומן במקום אחר (לבדיקות)");
            Console.WriteLine("  --task <שם>        שם אחר למשימה המתוזמנת (לבדיקות)");
            Console.WriteLine();
        }
    }
}
