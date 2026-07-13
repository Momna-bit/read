







Pehle terminal dekh -> git bash

(step by step check karna. Example node -v likh ke hit enter)
Phir check -> node -v
	      npm -v


npm create vite@latest call-dashboard -- --template react

(jab upper wala run karogi tou neeche options ayege usme se)

ESLint
Yes

Ctrl + C (ye server stop karne k liye hai)

cd ~/call-dashboard
code .

(jab vs code khule ga tab)
select src on the left panel
then right click on src and add new file
rename the file to call_forecast_dashboard.jsx
open the file and paste the code from github to the newly created file in vscode.

(ye karke phir terminal mein jana)

npm install recharts

npm list recharts


(neeche walay code b terminal mein run karna and make sure they are not empty)

npm list react
npm list react-dom

(finally neeche wala karna server live karne k liye)
npm run dev








TASK 2 & 3 
/* =====================================================================
   TASK 2: CALL-DRIVER ANALYSIS
   Goal: which customers are more likely to call, and why
   (product, tenure, channel, split-bill status)
   ===================================================================== */

-- STEP 1: Split-bill flag per bill (COUNT(DISTINCT Product), not row count)
;WITH BillProducts AS (
    SELECT
        BILL_NO,
        CUST_ID,
        COUNT(DISTINCT Product) AS DistinctProducts
    FROM iSigma_Bill_Contract_Details
    GROUP BY BILL_NO, CUST_ID
)
SELECT
    BILL_NO,
    CUST_ID,
    DistinctProducts,
    CASE WHEN DistinctProducts > 1 THEN 1 ELSE 0 END AS IsSplitBill
INTO #BillSplitFlags
FROM BillProducts;

-- STEP 2: What % of all bills are split?
SELECT
    COUNT(*) AS TotalBills,
    SUM(IsSplitBill) AS SplitBills,
    CAST(SUM(IsSplitBill) AS FLOAT) / COUNT(*) * 100.0 AS PctSplitBills
FROM #BillSplitFlags;

-- Optional: trend over time — join #BillSplitFlags back to iSigma_Bill_Master
-- on BILL_NO to get Bill_Date, then GROUP BY month.


-- STEP 3: Determine each customer's product/split-status per bill
;WITH RankedBills AS (
    SELECT
        bm.cust_id,
        bm.Bill_No,
        bm.Bill_Date,
        bm.Product,
        bsf.IsSplitBill,
        ROW_NUMBER() OVER (PARTITION BY bm.cust_id ORDER BY bm.Bill_Date DESC) AS rn
    FROM iSigma_Bill_Master bm
    LEFT JOIN #BillSplitFlags bsf ON bm.Bill_No = bsf.BILL_NO
)
SELECT * FROM RankedBills WHERE rn = 1;  -- sanity check: current bill per customer


-- STEP 4: Attach each call to the customer's most-recent bill as of that call date
;WITH ScopedCalls AS (
    SELECT
        ivr.ContactID,
        ivr.CustomerID,          -- CONFIRM actual column name in dbo.IVR
        CAST(ivr.CallDateTime AS DATE) AS CallDate
    FROM dbo.IVR ivr
    WHERE ivr.Department = 'Care'
      AND ivr.CallType IN ('Inbound','Transfer')
      AND ivr.AgentTalkTime > 0
),
CallWithBill AS (
    SELECT
        c.ContactID,
        c.CustomerID,
        c.CallDate,
        bm.Bill_No,
        bm.Product,
        bsf.IsSplitBill,
        ROW_NUMBER() OVER (PARTITION BY c.ContactID
                           ORDER BY bm.Bill_Date DESC) AS rn
    FROM ScopedCalls c
    JOIN iSigma_Bill_Master bm
        ON bm.cust_id = c.CustomerID
       AND bm.Bill_Date <= c.CallDate
    LEFT JOIN #BillSplitFlags bsf ON bm.Bill_No = bsf.BILL_NO
)
SELECT ContactID, CustomerID, CallDate, Bill_No, Product, IsSplitBill
INTO #CallsWithBillContext
FROM CallWithBill
WHERE rn = 1;


-- STEP 5: Call rate by product
SELECT
    Product,
    COUNT(*) AS Calls
FROM #CallsWithBillContext
GROUP BY Product
ORDER BY Calls DESC;

-- STEP 6: Call rate by split-bill status
SELECT
    IsSplitBill,
    COUNT(*) AS Calls
FROM #CallsWithBillContext
GROUP BY IsSplitBill;

-- To get RATES (not just counts), join #BillSplitFlags back to
-- iSigma_Customer_Master (Market='Texas', CustomerType='Residential')
-- for the denominator — same pattern as Task 1.

-- STEP 7 (placeholder — table/columns TBD):
-- Tenure: DATEDIFF(MONTH/DAY, FlowStart, CallDate) from iSigma_Customer_Master
-- Channel: field not yet identified — confirm with Jonathan/Aradhna.

DROP TABLE #BillSplitFlags;
DROP TABLE #CallsWithBillContext;






/* =====================================================================
   TASK 3: SPANISH / BILL-EXPLANATION FOLLOW-UP
   1. Quantify credit line item mentions (incl. Summer Saver) by language
   2. Reconcile Aradhna's method (9,394) vs Care_CallAI (24,776)
   3. Check whether deposit line items are untranslated (pending Jonathan)
   ===================================================================== */

-- STEP 1: Reconcile the definition gap — do this FIRST
SELECT
    cai.ContactID,
    cai.BillExplanationFlag,     -- CONFIRM actual column name in Care_CallAI
    CASE WHEN t.ContactID IS NOT NULL THEN 1 ELSE 0 END AS FlaggedByAradhnaMethod
FROM Care_CallAI cai
LEFT JOIN Care_AI_Transcripts t ON t.ContactID = cai.ContactID  -- CONFIRM join key
WHERE cai.CallDate BETWEEN @StartDate AND @EndDate;             -- match her original window

-- Then aggregate: flagged by BOTH / Care_CallAI ONLY / Aradhna's method ONLY.


-- STEP 2: Quantify credit line item mentions in bill-explanation calls, by language
;WITH BillExplanationCalls AS (
    SELECT ContactID, Language, CallDate      -- CONFIRM Language field source
    FROM Care_CallAI
    WHERE BillExplanationFlag = 1             -- CONFIRM column name
),
CreditLineItems AS (
    SELECT CUST_ID, Bill_No, LineItemDescription, CO_START_DATE
    FROM iSigma_Bill_Contract_Details           -- CONFIRM this is where credit lines live
    WHERE LineItemDescription LIKE '%Credit%'
)
SELECT
    bec.Language,
    cli.LineItemDescription,
    COUNT(DISTINCT bec.ContactID) AS CallsWithThisCreditLine
FROM BillExplanationCalls bec
JOIN CreditLineItems cli ON /* join on cust_id + date proximity to call, TBD */ 1=1
GROUP BY bec.Language, cli.LineItemDescription
ORDER BY bec.Language, CallsWithThisCreditLine DESC;

-- Isolate "Summer Saver Credit" specifically:
-- WHERE cli.LineItemDescription = 'Summer Saver Credit'


-- STEP 3: Deposit line items — hold until Jonathan confirms whether these
-- are untranslated on Spanish bills. Same query pattern as Step 2 once
-- confirmed, filtered to deposit-related line item descriptions.


