-- Run this by itself whenever you're re-running Step 1 (or any step)
-- individually instead of the whole script top-to-bottom.
IF OBJECT_ID('tempdb..#CustomerAttrition') IS NOT NULL DROP TABLE #CustomerAttrition;
IF OBJECT_ID('tempdb..#SampleCustomers') IS NOT NULL DROP TABLE #SampleCustomers;
IF OBJECT_ID('tempdb..#BatSmtSample') IS NOT NULL DROP TABLE #BatSmtSample;
