	
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


-- STEP 1: Confirm actual columns on iSigma_Bill_Master before building Task 7
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Bill_Master'
ORDER BY ORDINAL_POSITION;


-- ============================================================================
-- TASK 7: PROACTIVE USAGE & BILL SHOCK ALERT MODEL
-- STEP 2 (with baseline confidence flag)
-- ============================================================================

WITH Callers AS (
    SELECT DISTINCT ivr.AccountNumber AS cust_id
    FROM dbo.IVR ivr
    JOIN Care_CallAI cai ON cai.ContactID = ivr.ContactID
    WHERE ivr.Department = 'Care'
        AND ivr.CallType IN ('Inbound', 'Transfer')
        AND ivr.AgentTalkTime > 0
        AND cai.[call.reason] IN ('Bill Explanation', 'Bill Dispute')
        AND ivr.CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
        AND ivr.AccountNumber IS NOT NULL
),

RankedBills AS (
    SELECT bm.*,
        ROW_NUMBER() OVER (PARTITION BY bm.cust_id ORDER BY bm.Bill_Date DESC) AS rn
    FROM iSigma_Bill_Master bm
    JOIN Callers c ON c.cust_id = bm.cust_id
),

MostRecentBill AS (
    SELECT * FROM RankedBills WHERE rn = 1
),

PersonalBaseline AS (
    SELECT
        cust_id,
        AVG(NetCharge) AS BaselineNetCharge,
        AVG(Usage) AS BaselineUsage,
        COUNT(*) AS BaselineBillCount
    FROM RankedBills
    WHERE rn BETWEEN 2 AND 13
    GROUP BY cust_id
),

CustomerAttributes AS (
    SELECT
        cust_id,
        CreditScore,
        FlowStart,
        DATEDIFF(DAY, FlowStart, CAST(GETDATE() AS DATE)) AS TenureDays
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND CreditScore <> 0
)

SELECT
    mrb.cust_id,
    mrb.Bill_Date,
    mrb.NetCharge AS MostRecentNetCharge,
    pb.BaselineNetCharge,
    pb.BaselineBillCount,
    CASE 
        WHEN pb.BaselineBillCount >= 9 THEN 'High confidence'
        WHEN pb.BaselineBillCount >= 4 THEN 'Medium confidence'
        ELSE 'Low confidence (short tenure)'
    END AS BaselineConfidence,
    ROUND(mrb.NetCharge - pb.BaselineNetCharge, 2) AS DollarIncrease,
    ROUND((mrb.NetCharge - pb.BaselineNetCharge) / NULLIF(pb.BaselineNetCharge, 0) * 100, 2) AS PercentIncrease,
    mrb.Usage AS MostRecentUsage,
    pb.BaselineUsage,
    mrb.ServicePeriod AS ServicePeriodDays,
    ROUND((mrb.Usage - pb.BaselineUsage) / NULLIF(mrb.ServicePeriod, 0), 3) AS UsageIncreasePerDay,
    ca.CreditScore,
    ca.TenureDays
FROM MostRecentBill mrb
JOIN PersonalBaseline pb ON pb.cust_id = mrb.cust_id
JOIN CustomerAttributes ca ON ca.cust_id = mrb.cust_id
ORDER BY DollarIncrease DESC;
