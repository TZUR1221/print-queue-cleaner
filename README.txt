איפוס תור הדפסות
=================

מה זה:   יישום שרץ על המחשב כל 2 דקות ומוחק מתורי ההדפסה עבודות שנתקעו.
למה:     עבודה תקועה חוסמת את כל התור, ואז אף אחד בת"ת לא מצליח להדפיס.
איך מריצים: לוחצים פעמיים על "הפעלה.bat" לפתיחת חלון ההגדרות.
         ההרצה האוטומטית היא משימה מתוזמנת בשם PrintQueueCleaner.
         בדיקות: powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1
                 powershell -ExecutionPolicy Bypass -File tests\integration-test.ps1
GitHub:  טרם
סטטוס:   חי
תלויות:  PowerShell 5.1 בלבד (מובנה ב-Windows). אין התקנות, אין ספריות.

עודכן: 24/11/2026
