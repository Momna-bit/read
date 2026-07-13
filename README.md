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




/* =====================================================================
   TASK 2: CALL-DRIVER ANALYSIS — SPLIT-BILL vs CALL RATE
   Population: Texas, Residential, active customers (FlowStart IS NOT NULL,
   FlowEnd IS NULL), last 6 months of billing activity.
   Tested and confirmed working end-to-end.
   ===================================================================== */

-- STEP 1: Flag each bill as split or not (COUNT(DISTINCT Product) > 1),
--         scoped to active Texas residential customers, last 6 months.
IF OBJECT_ID('tempdb..#BillSplitFlags') IS NOT NULL DROP TABLE #BillSplitFlags;

;WITH BillProducts AS (
    SELECT
        bcd.BILL_NO,
        bcd.CUST_ID,
        COUNT(DISTINCT bcd.Product) AS DistinctProducts
    FROM iSigma_Bill_Contract_Details bcd
    JOIN iSigma_Customer_Master cm ON cm.cust_id = bcd.CUST_ID
    WHERE cm.Market = 'Texas'
      AND cm.CustomerType = 'Residential'
      AND cm.FlowStart IS NOT NULL
      AND cm.FlowEnd IS NULL
      AND bcd.CO_START_DATE >= DATEADD(MONTH, -6, GETDATE())
    GROUP BY bcd.BILL_NO, bcd.CUST_ID
)
SELECT
    BILL_NO,
    CUST_ID,
    DistinctProducts,
    CASE WHEN DistinctProducts > 1 THEN 1 ELSE 0 END AS IsSplitBill
INTO #BillSplitFlags
FROM BillProducts;

-- Result: 3,033,307 bills scoped.


-- STEP 2: What % of bills are split?
SELECT
    COUNT(*) AS TotalBills,
    SUM(IsSplitBill) AS SplitBills,
    CAST(SUM(IsSplitBill) AS FLOAT) / COUNT(*) * 100.0 AS PctSplitBills
FROM #BillSplitFlags;

-- KEY FINDING: ~10.6% of bills are split (322,920 of 3,033,307).


-- STEP 3: Attach each call to the customer's most recent bill as of that
--         call date.
IF OBJECT_ID('tempdb..#CallsWithBillContext') IS NOT NULL DROP TABLE #CallsWithBillContext;

;WITH ScopedCalls AS (
    SELECT
        ivr.ContactID,
        ivr.AccountNumber,
        CAST(ivr.CallDate AS DATE) AS CallDate
    FROM dbo.IVR ivr
    WHERE ivr.Department = 'Care'
      AND ivr.CallType IN ('Inbound','Transfer')
      AND ivr.AgentTalkTime > 0
),
CallWithBill AS (
    SELECT
        c.ContactID,
        c.AccountNumber,
        c.CallDate,
        bm.Bill_No,
        bm.Product,
        bsf.IsSplitBill,
        ROW_NUMBER() OVER (PARTITION BY c.ContactID ORDER BY bm.Bill_Date DESC) AS rn
    FROM ScopedCalls c
    JOIN iSigma_Bill_Master bm ON bm.cust_id = c.AccountNumber
       AND bm.Bill_Date <= c.CallDate
    LEFT JOIN #BillSplitFlags bsf ON bm.Bill_No = bsf.BILL_NO
)
SELECT ContactID, AccountNumber, CallDate, Bill_No, Product, IsSplitBill
INTO #CallsWithBillContext
FROM CallWithBill
WHERE rn = 1;

-- Result: 2,363,854 calls attached to bill context.


-- STEP 4: Raw call counts by split-bill status (in-scope calls only)
SELECT
    IsSplitBill,
    COUNT(*) AS Calls
FROM #CallsWithBillContext
WHERE IsSplitBill IS NOT NULL
GROUP BY IsSplitBill;

-- Result: Non-split = 174,237 calls | Split = 17,779 calls


-- STEP 5: Customer counts by split-bill status
;WITH CustomerSplitStatus AS (
    SELECT DISTINCT CUST_ID, IsSplitBill
    FROM #BillSplitFlags
)
SELECT
    IsSplitBill,
    COUNT(DISTINCT CUST_ID) AS Customers
FROM CustomerSplitStatus
GROUP BY IsSplitBill;

-- Result: Non-split = 563,285 customers | Split = 84,167 customers


-- STEP 6: THE HEADLINE NUMBER — calls per customer, by split-bill status
;WITH CustomerSplitStatus AS (
    SELECT DISTINCT CUST_ID, IsSplitBill
    FROM #BillSplitFlags
),
CustomerCounts AS (
    SELECT IsSplitBill, COUNT(DISTINCT CUST_ID) AS Customers
    FROM CustomerSplitStatus
    GROUP BY IsSplitBill
),
CallCounts AS (
    SELECT IsSplitBill, COUNT(*) AS Calls
    FROM #CallsWithBillContext
    WHERE IsSplitBill IS NOT NULL
    GROUP BY IsSplitBill
)
SELECT
    cc.IsSplitBill,
    cu.Customers,
    cc.Calls,
    CAST(cc.Calls AS FLOAT) / cu.Customers AS CallsPerCustomer
FROM CallCounts cc
JOIN CustomerCounts cu ON cc.IsSplitBill = cu.IsSplitBill;

-- KEY FINDING: Non-split = 0.309 calls/customer | Split = 0.211 calls/customer




/* =====================================================================
   TASK 3: SPANISH / BILL-EXPLANATION FOLLOW-UP
   Investigating what drives "Bill Explanation" calls, and whether a
   specific credit line item (e.g. Summer Saver Credit) is a meaningful
   driver. Uses Care_CallAI's own classification fields.
   Tested and confirmed working end-to-end.
   ===================================================================== */

-- STEP 1: Total bill-explanation calls per Care_CallAI's own classification
SELECT COUNT(DISTINCT ContactID) AS BillExplanationCalls
FROM Care_CallAI
WHERE [call.reason] = 'Bill Explanation';

-- Result: 26,882 calls. STILL UNRESOLVED: Aradhna's method produced 9,394
-- for the same population — needs reconciliation with her before either
-- number is presented as final.


-- STEP 2: Breakdown of bill-explanation calls by reason/sub-reason
SELECT
    [highbill.reason],
    [highbill.reasongranular],
    COUNT(DISTINCT ContactID) AS Calls
FROM Care_CallAI
WHERE [call.reason] = 'Bill Explanation'
GROUP BY [highbill.reason], [highbill.reasongranular]
ORDER BY Calls DESC;

-- KEY FINDING: ~25% of calls have no specific reason ("n/a"/"unknown").
-- Usage and Fee confusion dominate — not Credit.


-- STEP 3: Search specifically for "Summer Saver Credit" or similar
SELECT
    [highbill.reason],
    [highbill.reasongranular],
    [highbill.agentexplanation],
    COUNT(DISTINCT ContactID) AS Calls
FROM Care_CallAI
WHERE [call.reason] = 'Bill Explanation'
  AND ([highbill.reasongranular] LIKE '%Summer%' OR [highbill.agentexplanation] LIKE '%Summer%')
GROUP BY [highbill.reason], [highbill.reasongranular], [highbill.agentexplanation];

-- KEY FINDING: Every "Summer" match is about USAGE, not credit. The
-- "Summer Saver Credit" theory is NOT supported by this data.


-- STEP 4: Total credit-related bill-explanation calls
SELECT SUM(Calls) AS TotalCreditRelatedCalls
FROM (
    SELECT [highbill.reasongranular], COUNT(DISTINCT ContactID) AS Calls
    FROM Care_CallAI
    WHERE [call.reason] = 'Bill Explanation' AND [highbill.reason] = 'Credit'
    GROUP BY [highbill.reasongranular]
) t;

-- KEY FINDING: 1,756 of 26,882 (~6.5%) — real but a minor share.



