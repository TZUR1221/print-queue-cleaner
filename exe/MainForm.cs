// MainForm.cs — חלון ההגדרות בעברית. זה המסך היחיד שהמשתמש צריך.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Windows.Forms;

namespace PrintQueueCleaner
{
    internal sealed class MainForm : Form
    {
        private const string FontName = "Segoe UI";

        private CheckedListBox _clbPrinters;
        private List<string> _allPrinters;
        private NumericUpDown _numNoProgress, _numErrGrace, _numPrinted, _numSpooler;
        private CheckBox _chkError, _chkPaperOut, _chkPaused, _chkPrinted, _chkSpooler, _chkEnabled, _chkDryRun;
        private CheckBox _chkAtPrinter;
        private Label _lblStatus;
        private TextBox _txtLog;
        private Timer _timer;

        public MainForm()
        {
            Settings s = Storage.LoadSettings();

            Text = "איפוס תור הדפסות";
            Width = 700;
            Height = 993;
            StartPosition = FormStartPosition.CenterScreen;
            RightToLeft = RightToLeft.Yes;
            RightToLeftLayout = true;
            AutoScroll = true;
            BackColor = Color.FromArgb(248, 249, 251);
            Font = new Font(FontName, 10);
            MinimumSize = new Size(560, 520);
            // הפקדים ממוקמים בפיקסלים, ולכן צריך לתת ל-WinForms לשנות להם
            // קנה מידה כשהתצוגה אינה 100%. בלי זה החלון יוצא מטושטש או חתוך.
            AutoScaleMode = AutoScaleMode.Dpi;
            AutoScaleDimensions = new SizeF(96F, 96F);
            // מסך 1080 בתצוגה 125% לא מכיל חלון של 960 פיקסלים אחרי הגדלה;
            // מקצרים אותו למסך ונותנים ל-AutoScroll להשלים.
            Load += delegate
            {
                int maxH = Screen.FromControl(this).WorkingArea.Height - 40;
                if (Height > maxH) Height = maxH;
            };

            Controls.Add(Title("איפוס תור הדפסות", 20, 14, 400, 16, true));
            Label sub = Title("בודק את תורי ההדפסה כל 2 דקות ומוחק עבודות שנתקעו.", 20, 46, 620, 10, false);
            sub.ForeColor = Color.FromArgb(90, 95, 105);
            Controls.Add(sub);

            BuildPrintersGroup(s);
            BuildRulesGroup(s);
            BuildHardGroup(s);
            BuildStateGroup(s);
            BuildButtons();
            BuildLog();

            Shown += delegate
            {
                RefreshStatus();
                RefreshLog();
                _timer = new Timer { Interval = 10000 };
                _timer.Tick += delegate { RefreshStatus(); RefreshLog(); };
                _timer.Start();
            };
            FormClosed += delegate { if (_timer != null) { _timer.Stop(); _timer.Dispose(); } };
        }

        // ---------- עזרי בנייה ----------

        private static Label Title(string text, int x, int y, int w, int size, bool bold)
        {
            return new Label
            {
                Text = text, Left = x, Top = y, Width = w, Height = 22,
                Font = new Font(FontName, size, bold ? FontStyle.Bold : FontStyle.Regular)
            };
        }

        private static Label Hint(string text, int x, int y, int w)
        {
            return new Label
            {
                Text = text, Left = x, Top = y, Width = w, Height = 32,
                Font = new Font(FontName, 9),
                ForeColor = Color.FromArgb(120, 125, 135)
            };
        }

        private static CheckBox Chk(string text, int x, int y, int w, bool on)
        {
            return new CheckBox
            {
                Text = text, Left = x, Top = y, Width = w, Height = 24,
                Checked = on, Font = new Font(FontName, 10)
            };
        }

        private static NumericUpDown Num(int x, int y, int min, int max, int val)
        {
            return new NumericUpDown
            {
                Left = x, Top = y, Width = 70,
                Minimum = min, Maximum = max,
                Value = Math.Min(Math.Max(val, min), max),
                Font = new Font(FontName, 10),
                TextAlign = HorizontalAlignment.Center
            };
        }

        private static Button Btn(string text, int x, int y, int w)
        {
            return new Button
            {
                Text = text, Left = x, Top = y, Width = w, Height = 34,
                Font = new Font(FontName, 10), FlatStyle = FlatStyle.System
            };
        }

        private static GroupBox Group(string text, int top, int height)
        {
            return new GroupBox
            {
                Text = "  " + text + "  ", Left = 20, Top = top, Width = 640, Height = height,
                Font = new Font(FontName, 10, FontStyle.Bold), RightToLeft = RightToLeft.Yes
            };
        }

        // ---------- קבוצות ----------

        private void BuildPrintersGroup(Settings s)
        {
            GroupBox g = Group("מדפסות שבטיפול", 80, 205);

            _clbPrinters = new CheckedListBox
            {
                Left = 15, Top = 28, Width = 610, Height = 130,
                Font = new Font(FontName, 10), RightToLeft = RightToLeft.Yes, CheckOnClick = true
            };

            _allPrinters = Spooler.InstalledPrinters();
            _allPrinters.Sort(StringComparer.CurrentCulture);
            foreach (string p in _allPrinters)
                _clbPrinters.Items.Add(p, s.Printers.Count > 0 && s.Printers.Contains(p));

            Button all = Btn("סמן הכל", 15, 164, 110);
            Button none = Btn("נקה הכל", 135, 164, 110);
            all.Click += delegate { SetAllChecked(true); };
            none.Click += delegate { SetAllChecked(false); };

            g.Controls.Add(_clbPrinters);
            g.Controls.Add(all);
            g.Controls.Add(none);
            g.Controls.Add(Hint("אם לא סומנה אף מדפסת — המערכת תטפל בכל המדפסות.", 255, 170, 370));
            Controls.Add(g);
        }

        private void SetAllChecked(bool on)
        {
            for (int i = 0; i < _clbPrinters.Items.Count; i++) _clbPrinters.SetItemChecked(i, on);
        }

        private void BuildRulesGroup(Settings s)
        {
            GroupBox g = Group("מתי למחוק עבודה", 292, 248);

            _numNoProgress = Num(15, 30, 1, 240, s.MinutesNoProgress);
            _chkError = Chk("למחוק עבודה שנמצאת בשגיאה או שהמדפסת לא מחוברת", 15, 64, 440, s.DeleteOnError);
            _numErrGrace = Num(35, 92, 0, 60, s.ErrorGraceMinutes);
            _chkPaperOut = Chk("למחוק גם עבודה שממתינה לנייר או להתערבות (לא מומלץ)", 15, 120, 440, s.DeletePaperOut);
            _chkPaused = Chk("למחוק גם עבודה שמישהו השהה בכוונה (לא מומלץ)", 15, 146, 440, s.DeletePaused);
            _chkPrinted = Chk("לנקות עבודות שכבר הודפסו ונשארו בתור, לאחר", 15, 172, 330, s.DeletePrintedLeftovers);
            _numPrinted = Num(350, 170, 1, 240, s.PrintedLeftoverMinutes);
            _chkAtPrinter = Chk("לא לגעת בעבודה שכבר התחילה לעבור למדפסת", 15, 200, 440, s.SkipJobsAtPrinter);

            _chkError.CheckedChanged += delegate { _numErrGrace.Enabled = _chkError.Checked; };
            _numErrGrace.Enabled = _chkError.Checked;
            _chkPrinted.CheckedChanged += delegate { _numPrinted.Enabled = _chkPrinted.Checked; };
            _numPrinted.Enabled = _chkPrinted.Checked;

            g.Controls.Add(_numNoProgress);
            g.Controls.Add(Title("דקות שעבודה עומדת בלי להתקדם — ואז נמחקת", 95, 33, 400, 10, false));
            g.Controls.Add(_chkError);
            g.Controls.Add(_numErrGrace);
            g.Controls.Add(Hint("דקות המתנה לפני מחיקת עבודה בשגיאה (למקרה של תקלה רגעית)", 115, 95, 420));
            g.Controls.Add(_chkPaperOut);
            g.Controls.Add(_chkPaused);
            g.Controls.Add(_chkPrinted);
            g.Controls.Add(_numPrinted);
            g.Controls.Add(Title("דקות", 425, 173, 60, 10, false));
            g.Controls.Add(_chkAtPrinter);
            g.Controls.Add(Hint("כשהמתג דלוק, עבודה שנתוניה כבר זורמים למכונה לא תימחק — גם אם נתקעה.", 35, 224, 590));
            Controls.Add(g);
        }

        private void BuildHardGroup(Settings s)
        {
            GroupBox g = Group("עבודה שמסרבת להימחק", 546, 100);

            _chkSpooler = Chk("לאפס את שירות ההדפסה של Windows אחרי", 15, 30, 300, s.SpoolerResetEnabled);
            _numSpooler = Num(320, 28, 1, 20, s.SpoolerResetAfterAttempts);
            _numSpooler.Enabled = _chkSpooler.Checked;
            _chkSpooler.CheckedChanged += delegate { _numSpooler.Enabled = _chkSpooler.Checked; };

            g.Controls.Add(_chkSpooler);
            g.Controls.Add(_numSpooler);
            g.Controls.Add(Title("נסיונות מחיקה כושלים", 395, 31, 200, 10, false));
            g.Controls.Add(Hint("איפוס השירות משחרר עבודה נעולה, אך רק כשאין באותו רגע הדפסה שמתקדמת.", 15, 60, 600));
            Controls.Add(g);
        }

        private void BuildStateGroup(Settings s)
        {
            GroupBox g = Group("מצב המערכת", 653, 105);

            _chkEnabled = Chk("המערכת פעילה", 15, 28, 180, s.Enabled);
            _chkDryRun = Chk("מצב בדיקה — רק לרשום ביומן, בלי למחוק באמת", 200, 28, 420, s.DryRun);
            _lblStatus = Hint("בודק...", 15, 56, 605);
            _lblStatus.Height = 44;

            g.Controls.Add(_chkEnabled);
            g.Controls.Add(_chkDryRun);
            g.Controls.Add(_lblStatus);
            Controls.Add(g);
        }

        private void BuildButtons()
        {
            Button save = Btn("שמור הגדרות", 20, 768, 140);
            Button run = Btn("בדוק עכשיו", 168, 768, 120);
            Button install = Btn("הפעל כל 2 דקות", 296, 768, 150);
            Button remove = Btn("בטל הרצה אוטומטית", 454, 768, 160);
            save.BackColor = Color.FromArgb(222, 235, 255);

            save.Click += delegate { DoSave(true); };
            run.Click += delegate { DoRunNow(); };
            install.Click += delegate { DoInstall(); };
            remove.Click += delegate { DoUninstall(); };

            Controls.Add(save); Controls.Add(run); Controls.Add(install); Controls.Add(remove);
        }

        private void BuildLog()
        {
            Controls.Add(Title("יומן הפעולות האחרונות:", 20, 812, 300, 10, true));
            Button open = Btn("פתח את קובץ היומן", 500, 806, 125);
            open.Click += delegate
            {
                string f = Storage.CurrentLogFile();
                if (File.Exists(f)) Process.Start("notepad.exe", "\"" + f + "\"");
                else Info("אין עדיין קובץ יומן לחודש הזה.");
            };
            Controls.Add(open);

            _txtLog = new TextBox
            {
                Left = 20, Top = 838, Width = 640, Height = 110,
                Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical,
                RightToLeft = RightToLeft.Yes, BackColor = Color.White,
                Font = new Font("Consolas", 9)
            };
            Controls.Add(_txtLog);
        }

        // ---------- פעולות ----------

        private Settings FromUi()
        {
            var chosen = new List<string>();
            for (int i = 0; i < _clbPrinters.Items.Count; i++)
                if (_clbPrinters.GetItemChecked(i)) chosen.Add(_allPrinters[i]);

            // סומנו כולן => נשמרת רשימה ריקה, שמשמעותה "כל המדפסות,
            // גם אחת שתתווסף בעתיד"
            if (chosen.Count == _clbPrinters.Items.Count) chosen.Clear();

            return new Settings
            {
                Enabled = _chkEnabled.Checked,
                DryRun = _chkDryRun.Checked,
                Printers = chosen,
                MinutesNoProgress = (int)_numNoProgress.Value,
                ErrorGraceMinutes = (int)_numErrGrace.Value,
                DeleteOnError = _chkError.Checked,
                DeletePaperOut = _chkPaperOut.Checked,
                DeletePaused = _chkPaused.Checked,
                SkipJobsAtPrinter = _chkAtPrinter.Checked,
                DeletePrintedLeftovers = _chkPrinted.Checked,
                PrintedLeftoverMinutes = (int)_numPrinted.Value,
                SpoolerResetEnabled = _chkSpooler.Checked,
                SpoolerResetAfterAttempts = (int)_numSpooler.Value
            };
        }

        private bool DoSave(bool announce)
        {
            try
            {
                Storage.SaveSettings(FromUi());
                Storage.Log("ההגדרות נשמרו מהמסך.", "פעולה");
                RefreshLog();
                if (announce) Info("ההגדרות נשמרו.");
                return true;
            }
            catch (Exception ex) { Error("השמירה נכשלה: " + ex.Message); return false; }
        }

        private void DoRunNow()
        {
            if (!DoSave(false)) return;
            Cursor = Cursors.WaitCursor;
            var lines = new List<string>();
            try { Scanner.RunOnce(false, delegate(string m) { lines.Add(m); }); }
            catch (Exception ex) { lines.Add("שגיאה: " + ex.Message); }
            Cursor = Cursors.Default;
            RefreshStatus(); RefreshLog();
            Info(string.Join(Environment.NewLine, lines.ToArray()));
        }

        private void DoInstall()
        {
            if (!DoSave(false)) return;
            try
            {
                if (Storage.IsElevated()) TaskInstaller.Install();
                else if (!RunElevated("--install")) return;     // המשתמש ביטל את אישור המנהל
                RefreshStatus(); RefreshLog();
                Info("ההרצה האוטומטית הותקנה. מעתה המחשב בודק את התור כל 2 דקות, גם כשאף אחד לא מחובר.");
            }
            catch (Exception ex) { Error("ההתקנה נכשלה: " + ex.Message); }
        }

        private void DoUninstall()
        {
            try
            {
                if (Storage.IsElevated()) TaskInstaller.Uninstall();
                else if (!RunElevated("--uninstall")) return;
                RefreshStatus(); RefreshLog();
                Info("ההרצה האוטומטית הוסרה.");
            }
            catch (Exception ex) { Error("ההסרה נכשלה: " + ex.Message); }
        }

        // החלון נפתח בלי הרשאות מנהל, כדי שלא יקפוץ UAC על כל פתיחה.
        // הרשאות נדרשות רק להתקנה ולהסרה של ההרצה האוטומטית, ואז ה-exe
        // מפעיל את עצמו מחדש עם הדגל המתאים — אישור אחד, ברגע הנכון.
        // מחזיר false אם המשתמש ביטל את האישור.
        private bool RunElevated(string arguments)
        {
            string exe = Process.GetCurrentProcess().MainModule.FileName;
            // מעבירים את שם המשימה ואת תיקיית הנתונים הלאה, אחרת התהליך
            // המורם היה עובד על ברירות המחדל ולא על מה שמוצג בחלון.
            string args = arguments + " --task \"" + TaskInstaller.TaskName + "\"";
            if (Storage.DataDirWasOverridden)
                args += " --data \"" + Storage.DataDir + "\"";

            var psi = new ProcessStartInfo(exe, args)
            {
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Hidden
            };
            try
            {
                using (Process p = Process.Start(psi))
                {
                    p.WaitForExit(60000);
                    if (p.ExitCode != 0)
                        throw new InvalidOperationException(
                            "ההרצה בהרשאות מנהל הסתיימה בשגיאה (קוד " + p.ExitCode + "). היומן מכיל את הפרטים.");
                }
                return true;
            }
            catch (System.ComponentModel.Win32Exception w)
            {
                // 1223 = המשתמש לחץ "לא" באישור המנהל. זו אינה שגיאה.
                // (נכתב כך ולא כ-exception filter, כי המהדר המובנה הוא C# 5.)
                if (w.NativeErrorCode == 1223) return false;
                throw;
            }
        }

        // ---------- רענון ----------

        private void RefreshStatus()
        {
            var parts = new List<string>();

            TaskState ts = TaskInstaller.GetState();
            if (ts.Error != null) parts.Add("לא ניתן לקרוא את מצב ההרצה האוטומטית: " + ts.Error);
            else if (ts.Installed) parts.Add("הרצה אוטומטית: מותקנת");
            else parts.Add("הרצה אוטומטית: לא מותקנת — לחץ \"הפעל כל 2 דקות\"");

            Storage.RunStatus r = Storage.LoadRunStatus();
            if (r.Valid)
            {
                int ago = (int)(DateTime.Now - r.Time).TotalMinutes;
                string agoText = ago <= 0 ? "ממש עכשיו" : (ago == 1 ? "לפני דקה" : "לפני " + ago + " דקות");
                parts.Add(string.Format("סריקה אחרונה {0} ({1}): {2} בתור, נמחקו {3}",
                          agoText, r.Time.ToString("HH:mm:ss", CultureInfo.InvariantCulture),
                          r.Scanned, r.Deleted));
            }
            else parts.Add("עדיין לא בוצעה אף סריקה");

            if (!Storage.IsElevated())
                parts.Add("שים לב: החלון אינו בהרשאות מנהל — התקנה/הסרה של ההרצה האוטומטית לא תעבוד.");

            _lblStatus.Text = string.Join("   |   ", parts.ToArray());
        }

        private void RefreshLog()
        {
            string[] lines = Storage.LogTail(80);
            if (lines.Length == 0) { _txtLog.Text = "אין רשומות ביומן עדיין."; return; }
            Array.Reverse(lines);   // החדש למעלה
            _txtLog.Lines = lines;
        }

        // ---------- תיבות הודעה ----------

        private const MessageBoxOptions Rtl = MessageBoxOptions.RtlReading | MessageBoxOptions.RightAlign;

        private void Info(string text)
        {
            MessageBox.Show(this, text, "איפוס תור הדפסות",
                MessageBoxButtons.OK, MessageBoxIcon.Information,
                MessageBoxDefaultButton.Button1, Rtl);
        }

        private void Error(string text)
        {
            MessageBox.Show(this, text, "שגיאה",
                MessageBoxButtons.OK, MessageBoxIcon.Error,
                MessageBoxDefaultButton.Button1, Rtl);
        }

        // ---------- בדיקת בנייה ללא הצגה ----------

        public static int SelfCheck()
        {
            using (var f = new MainForm())
            {
                int n = Count(f);
                Console.WriteLine(string.Format(
                    "החלון נבנה בהצלחה: {0} פקדים, גודל {1}x{2}, מדפסות ברשימה: {3}",
                    n, f.Width, f.Height, f._clbPrinters.Items.Count));
                f.RefreshStatus();
                Console.WriteLine("שורת המצב: " + f._lblStatus.Text);
                return n > 0 ? 0 : 1;
            }
        }

        private static int Count(Control c)
        {
            int n = 0;
            foreach (Control x in c.Controls) { n++; n += Count(x); }
            return n;
        }
    }
}
