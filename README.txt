איפוס תור הדפסות
=================

מה זה:   יישום שרץ על המחשב כל 2 דקות ומוחק מתורי ההדפסה עבודות שנתקעו.
למה:     עבודה תקועה חוסמת את כל התור, ואז אף אחד בת"ת לא מצליח להדפיס.
איך מריצים: *** מה שרץ על המחשב הזה הוא גרסת ה-exe ***
         C:\PrintQueueCleaner\PrintQueueCleaner.exe  (קיצור בשולחן העבודה).
         גרסת הסקריפטים ב-src\ נשארת כקוד וכגיבוי, אך אינה המותקנת.
         ההרצה האוטומטית היא משימה מתוזמנת בשם PrintQueueCleaner.
         בדיקות: powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1
                 powershell -ExecutionPolicy Bypass -File tests\integration-test.ps1
GitHub:  https://github.com/TZUR1221/print-queue-cleaner  (ציבורי, MIT)
סטטוס:   חי
תלויות:  אין. ה-exe דורש .NET Framework 4.x שמובנה בחלונות;
         גרסת הסקריפטים דורשת PowerShell 5.1 שמובנה גם הוא.

עודכן: 25/11/2026
