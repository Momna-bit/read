	
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


-- STEP 1: Build per-customer feature set for usage-alert predictive score
-- Features: bill increase % vs personal historical median, credit score, tenure (days)
-- Label: did the customer call within 14 days of this bill (1) or not (0)

WITH BillHistory AS (
    SELECT
        b.cust_id,
        b.Bill_Date,
        CAST(b.inv_amount AS DECIMAL(10,2)) AS inv_amount,
        c.CreditScore,
        c.FlowStart
    FROM iSigma_Bill_Master b
    INNER JOIN iSigma_Customer_Master c
        ON b.cust_id = c.cust_id
    WHERE c.Market = 'Texas'
      AND c.CustomerType = 'Residential'
),
MedianCalc AS (
    SELECT
        b1.cust_id,
        b1.Bill_Date,
        b1.inv_amount,
        b1.CreditScore,
        b1.FlowStart,
        m.PersonalMedianCharge
    FROM BillHistory b1
    CROSS APPLY (
        SELECT AVG(inv_amount) AS PersonalMedianCharge
        FROM (
            SELECT
                inv_amount,
                ROW_NUMBER() OVER (ORDER BY inv_amount) AS rn,
                COUNT(*) OVER () AS cnt
            FROM BillHistory b2
            WHERE b2.cust_id = b1.cust_id
              AND b2.Bill_Date < b1.Bill_Date
        ) ranked
        WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    ) m
),
FeatureSet AS (
    SELECT
        cust_id,
        Bill_Date,
        inv_amount,
        PersonalMedianCharge,
        CASE WHEN PersonalMedianCharge > 0
             THEN (inv_amount - PersonalMedianCharge) / PersonalMedianCharge * 100.0
             ELSE NULL END AS BillIncreasePct,
        CreditScore,
        DATEDIFF(DAY, FlowStart, Bill_Date) AS TenureDays
    FROM MedianCalc
    WHERE PersonalMedianCharge IS NOT NULL
      AND CreditScore IS NOT NULL AND CreditScore != 0
)
SELECT
    f.*,
    CASE WHEN EXISTS (
        SELECT 1 FROM vw_Care_CustomerContact cc
        WHERE cc.AccountID = f.cust_id
          AND cc.CallDate BETWEEN f.Bill_Date AND DATEADD(DAY, 14, f.Bill_Date)
    ) THEN 1 ELSE 0 END AS CalledWithin14Days
FROM FeatureSet f


CAST(b.inv_amount AS DECIMAL(18,2)) AS inv_amount



WITH BillHistory AS (
    SELECT
        b.cust_id,
        b.Bill_Date,
        CAST(b.inv_amount AS DECIMAL(18,2)) AS inv_amount,
        c.CreditScore,
        c.FlowStart
    FROM iSigma_Bill_Master b
    INNER JOIN iSigma_Customer_Master c
        ON b.cust_id = c.cust_id
    WHERE c.Market = 'Texas'
      AND c.CustomerType = 'Residential'
),
Ranked AS (
    SELECT
        cust_id,
        Bill_Date,
        inv_amount,
        CreditScore,
        FlowStart,
        ROW_NUMBER() OVER (PARTITION BY cust_id ORDER BY Bill_Date) AS rn,
        COUNT(*) OVER (PARTITION BY cust_id) AS total_bills
    FROM BillHistory
),
MedianPerCust AS (
    SELECT
        cust_id,
        AVG(inv_amount) AS PersonalMedianCharge
    FROM (
        SELECT
            cust_id,
            inv_amount,
            ROW_NUMBER() OVER (PARTITION BY cust_id ORDER BY inv_amount) AS med_rn,
            COUNT(*) OVER (PARTITION BY cust_id) AS cnt
        FROM BillHistory
    ) x
    WHERE med_rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    GROUP BY cust_id
),
FeatureSet AS (
    SELECT
        r.cust_id,
        r.Bill_Date,
        r.inv_amount,
        m.PersonalMedianCharge,
        CASE WHEN m.PersonalMedianCharge > 0
             THEN (r.inv_amount - m.PersonalMedianCharge) / m.PersonalMedianCharge * 100.0
             ELSE NULL END AS BillIncreasePct,
        r.CreditScore,
        DATEDIFF(DAY, r.FlowStart, r.Bill_Date) AS TenureDays
    FROM Ranked r
    INNER JOIN MedianPerCust m ON r.cust_id = m.cust_id
    WHERE m.PersonalMedianCharge IS NOT NULL
      AND r.CreditScore IS NOT NULL AND r.CreditScore != 0
)
SELECT
    f.*,
    CASE WHEN EXISTS (
        SELECT 1 FROM vw_Care_CustomerContact cc
        WHERE cc.AccountID = f.cust_id
          AND cc.CallDate BETWEEN f.Bill_Date AND DATEADD(DAY, 14, f.Bill_Date)
    ) THEN 1 ELSE 0 END AS CalledWithin14Days
FROM FeatureSet f


-- STEP 1: Build per-customer feature set for usage-alert predictive score
-- Features: bill increase % vs personal historical median, credit score, tenure (days)
-- Label: did the customer call within 14 days of this bill (1) or not (0)
-- TEST SCOPE: limited to 2024+ bills for speed — remove filter once validated

WITH BillHistory AS (
    SELECT
        b.cust_id,
        b.Bill_Date,
        CAST(b.inv_amount AS DECIMAL(18,2)) AS inv_amount,
        c.CreditScore,
        c.FlowStart
    FROM iSigma_Bill_Master b
    INNER JOIN iSigma_Customer_Master c
        ON b.cust_id = c.cust_id
    WHERE c.Market = 'Texas'
      AND c.CustomerType = 'Residential'
      AND b.Bill_Date >= '2024-01-01'
),
Ranked AS (
    SELECT
        cust_id,
        Bill_Date,
        inv_amount,
        CreditScore,
        FlowStart,
        ROW_NUMBER() OVER (PARTITION BY cust_id ORDER BY Bill_Date) AS rn,
        COUNT(*) OVER (PARTITION BY cust_id) AS total_bills
    FROM BillHistory
),
MedianPerCust AS (
    SELECT
        cust_id,
        AVG(inv_amount) AS PersonalMedianCharge
    FROM (
        SELECT
            cust_id,
            inv_amount,
            ROW_NUMBER() OVER (PARTITION BY cust_id ORDER BY inv_amount) AS med_rn,
            COUNT(*) OVER (PARTITION BY cust_id) AS cnt
        FROM BillHistory
    ) x
    WHERE med_rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    GROUP BY cust_id
),
FeatureSet AS (
    SELECT
        r.cust_id,
        r.Bill_Date,
        r.inv_amount,
        m.PersonalMedianCharge,
        CASE WHEN m.PersonalMedianCharge > 0
             THEN (r.inv_amount - m.PersonalMedianCharge) / m.PersonalMedianCharge * 100.0
             ELSE NULL END AS BillIncreasePct,
        r.CreditScore,
        DATEDIFF(DAY, r.FlowStart, r.Bill_Date) AS TenureDays
    FROM Ranked r
    INNER JOIN MedianPerCust m ON r.cust_id = m.cust_id
    WHERE m.PersonalMedianCharge IS NOT NULL
      AND r.CreditScore IS NOT NULL AND r.CreditScore != 0
),
CallsByCustomer AS (
    SELECT DISTINCT AccountID AS cust_id, CallDate
    FROM vw_Care_CustomerContact
)
SELECT
    f.*,
    CASE WHEN EXISTS (
        SELECT 1 FROM CallsByCustomer c
        WHERE c.cust_id = f.cust_id
          AND c.CallDate BETWEEN f.Bill_Date AND DATEADD(DAY, 14, f.Bill_Date)
    ) THEN 1 ELSE 0 END AS CalledWithin14Days
FROM FeatureSet f



WITH BillHistory AS (
    SELECT
        b.cust_id,
        b.Bill_Date,
        CAST(b.inv_amount AS DECIMAL(18,2)) AS inv_amount,
        c.CreditScore,
        c.FlowStart
    FROM iSigma_Bill_Master b
    INNER JOIN iSigma_Customer_Master c
        ON b.cust_id = c.cust_id
    WHERE c.Market = 'Texas'
      AND c.CustomerType = 'Residential'
      AND b.Bill_Date >= '2024-01-01'
),
Ranked AS (
    SELECT
        cust_id, Bill_Date, inv_amount, CreditScore, FlowStart
    FROM BillHistory
),
MedianPerCust AS (
    SELECT
        cust_id,
        AVG(inv_amount) AS PersonalMedianCharge
    FROM (
        SELECT
            cust_id,
            inv_amount,
            ROW_NUMBER() OVER (PARTITION BY cust_id ORDER BY inv_amount) AS med_rn,
            COUNT(*) OVER (PARTITION BY cust_id) AS cnt
        FROM BillHistory
    ) x
    WHERE med_rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    GROUP BY cust_id
),
FeatureSet AS (
    SELECT
        r.cust_id,
        r.Bill_Date,
        r.inv_amount,
        m.PersonalMedianCharge,
        CASE WHEN m.PersonalMedianCharge > 0
             THEN (r.inv_amount - m.PersonalMedianCharge) / m.PersonalMedianCharge * 100.0
             ELSE NULL END AS BillIncreasePct,
        r.CreditScore,
        DATEDIFF(DAY, r.FlowStart, r.Bill_Date) AS TenureDays
    FROM Ranked r
    INNER JOIN MedianPerCust m ON r.cust_id = m.cust_id
    WHERE m.PersonalMedianCharge IS NOT NULL
      AND r.CreditScore IS NOT NULL AND r.CreditScore != 0
),
CallsByCustomer AS (
    SELECT DISTINCT AccountID AS cust_id, CallDate
    FROM vw_Care_CustomerContact
),
Final AS (
    SELECT
        f.*,
        CASE WHEN EXISTS (
            SELECT 1 FROM CallsByCustomer c
            WHERE c.cust_id = f.cust_id
              AND c.CallDate BETWEEN f.Bill_Date AND DATEADD(DAY, 14, f.Bill_Date)
        ) THEN 1 ELSE 0 END AS CalledWithin14Days
    FROM FeatureSet f
)
SELECT CalledWithin14Days, COUNT(*) AS RowCount
FROM Final
GROUP BY CalledWithin14Days




WITH BillHistory AS (
    SELECT
        b.cust_id,
        b.Bill_Date,
        CAST(b.inv_amount AS DECIMAL(18,2)) AS inv_amount,
        c.CreditScore,
        c.FlowStart
    FROM iSigma_Bill_Master b
    INNER JOIN iSigma_Customer_Master c
        ON b.cust_id = c.cust_id
    WHERE c.Market = 'Texas'
      AND c.CustomerType = 'Residential'
      AND b.Bill_Date >= '2024-01-01'
),
MedianPerCust AS (
    SELECT
        cust_id,
        AVG(inv_amount) AS PersonalMedianCharge
    FROM (
        SELECT
            cust_id,
            inv_amount,
            ROW_NUMBER() OVER (PARTITION BY cust_id ORDER BY inv_amount) AS med_rn,
            COUNT(*) OVER (PARTITION BY cust_id) AS cnt
        FROM BillHistory
    ) x
    WHERE med_rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    GROUP BY cust_id
),
FeatureSet AS (
    SELECT
        b.cust_id,
        b.Bill_Date,
        b.inv_amount,
        m.PersonalMedianCharge,
        CASE WHEN m.PersonalMedianCharge > 0
             THEN (b.inv_amount - m.PersonalMedianCharge) / m.PersonalMedianCharge * 100.0
             ELSE NULL END AS BillIncreasePct,
        b.CreditScore,
        DATEDIFF(DAY, b.FlowStart, b.Bill_Date) AS TenureDays
    FROM BillHistory b
    INNER JOIN MedianPerCust m ON b.cust_id = m.cust_id
    WHERE m.PersonalMedianCharge IS NOT NULL
      AND b.CreditScore IS NOT NULL AND b.CreditScore != 0
),
CallsByCustomer AS (
    SELECT DISTINCT AccountID AS cust_id, CallDate
    FROM vw_Care_CustomerContact
),
Final AS (
    SELECT
        f.*,
        CASE WHEN EXISTS (
            SELECT 1 FROM CallsByCustomer c
            WHERE c.cust_id = f.cust_id
              AND c.CallDate BETWEEN f.Bill_Date AND DATEADD(DAY, 14, f.Bill_Date)
        ) THEN 1 ELSE 0 END AS CalledWithin14Days
    FROM FeatureSet f
)
SELECT CalledWithin14Days, COUNT(*) AS RowCount
FROM Final
GROUP BY CalledWithin14Days





WITH BillHistory AS (
    SELECT
        b.cust_id,
        b.Bill_Date,
        CAST(b.inv_amount AS DECIMAL(18,2)) AS inv_amount,
        c.CreditScore,
        c.FlowStart
    FROM iSigma_Bill_Master b
    INNER JOIN iSigma_Customer_Master c
        ON b.cust_id = c.cust_id
    WHERE c.Market = 'Texas'
      AND c.CustomerType = 'Residential'
      AND b.Bill_Date >= '2024-01-01'
),
MedianPerCust AS (
    SELECT
        cust_id,
        AVG(inv_amount) AS PersonalMedianCharge
    FROM (
        SELECT
            cust_id,
            inv_amount,
            ROW_NUMBER() OVER (PARTITION BY cust_id ORDER BY inv_amount) AS med_rn,
            COUNT(*) OVER (PARTITION BY cust_id) AS cnt
        FROM BillHistory
    ) x
    WHERE med_rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    GROUP BY cust_id
),
FeatureSet AS (
    SELECT
        b.cust_id,
        b.Bill_Date,
        b.inv_amount,
        m.PersonalMedianCharge,
        CASE WHEN m.PersonalMedianCharge > 0
             THEN (b.inv_amount - m.PersonalMedianCharge) / m.PersonalMedianCharge * 100.0
             ELSE NULL END AS BillIncreasePct,
        b.CreditScore,
        DATEDIFF(DAY, b.FlowStart, b.Bill_Date) AS TenureDays
    FROM BillHistory b
    INNER JOIN MedianPerCust m ON b.cust_id = m.cust_id
    WHERE m.PersonalMedianCharge IS NOT NULL
      AND b.CreditScore IS NOT NULL AND b.CreditScore != 0
),
CallsByCustomer AS (
    SELECT DISTINCT AccountID AS cust_id, CallDate
    FROM vw_Care_CustomerContact
),
Final AS (
    SELECT
        f.*,
        CASE WHEN EXISTS (
            SELECT 1 FROM CallsByCustomer c
            WHERE c.cust_id = f.cust_id
              AND c.CallDate BETWEEN f.Bill_Date AND DATEADD(DAY, 14, f.Bill_Date)
        ) THEN 1 ELSE 0 END AS CalledWithin14Days
    FROM FeatureSet f
)
SELECT CalledWithin14Days, COUNT(*) AS BillCount
FROM Final
GROUP BY CalledWithin14Days



SELECT COUNT(*) AS TotalRows, COUNT(DISTINCT AccountID) AS DistinctAccounts
FROM vw_Care_CustomerContact



SELECT TOP 5 AccountID FROM vw_Care_CustomerContact
SELECT TOP 5 cust_id FROM iSigma_Customer_Master


SELECT TOP 5 CustID FROM vw_Care_CustomerContact


WITH BillHistory AS (
    SELECT
        b.cust_id,
        b.Bill_Date,
        CAST(b.inv_amount AS DECIMAL(18,2)) AS inv_amount,
        c.CreditScore,
        c.FlowStart
    FROM iSigma_Bill_Master b
    INNER JOIN iSigma_Customer_Master c
        ON b.cust_id = c.cust_id
    WHERE c.Market = 'Texas'
      AND c.CustomerType = 'Residential'
      AND b.Bill_Date >= '2024-01-01'
),
MedianPerCust AS (
    SELECT
        cust_id,
        AVG(inv_amount) AS PersonalMedianCharge
    FROM (
        SELECT
            cust_id,
            inv_amount,
            ROW_NUMBER() OVER (PARTITION BY cust_id ORDER BY inv_amount) AS med_rn,
            COUNT(*) OVER (PARTITION BY cust_id) AS cnt
        FROM BillHistory
    ) x
    WHERE med_rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    GROUP BY cust_id
),
FeatureSet AS (
    SELECT
        b.cust_id,
        b.Bill_Date,
        b.inv_amount,
        m.PersonalMedianCharge,
        CASE WHEN m.PersonalMedianCharge > 0
             THEN (b.inv_amount - m.PersonalMedianCharge) / m.PersonalMedianCharge * 100.0
             ELSE NULL END AS BillIncreasePct,
        b.CreditScore,
        DATEDIFF(DAY, b.FlowStart, b.Bill_Date) AS TenureDays
    FROM BillHistory b
    INNER JOIN MedianPerCust m ON b.cust_id = m.cust_id
    WHERE m.PersonalMedianCharge IS NOT NULL
      AND b.CreditScore IS NOT NULL AND b.CreditScore != 0
),
CallsByCustomer AS (
    SELECT DISTINCT CustID AS cust_id, CallDate
    FROM vw_Care_CustomerContact
),
Final AS (
    SELECT
        f.*,
        CASE WHEN EXISTS (
            SELECT 1 FROM CallsByCustomer c
            WHERE c.cust_id = f.cust_id
              AND c.CallDate BETWEEN f.Bill_Date AND DATEADD(DAY, 14, f.Bill_Date)
        ) THEN 1 ELSE 0 END AS CalledWithin14Days
    FROM FeatureSet f
)
SELECT CalledWithin14Days, COUNT(*) AS BillCount
FROM Final
GROUP BY CalledWithin14Days



WITH BillHistory AS (
    SELECT
        b.cust_id,
        b.Bill_Date,
        CAST(b.inv_amount AS DECIMAL(18,2)) AS inv_amount,
        c.CreditScore,
        c.FlowStart
    FROM iSigma_Bill_Master b
    INNER JOIN iSigma_Customer_Master c
        ON b.cust_id = c.cust_id
    WHERE c.Market = 'Texas'
      AND c.CustomerType = 'Residential'
      AND b.Bill_Date >= '2024-01-01'
),
MedianPerCust AS (
    SELECT
        cust_id,
        AVG(inv_amount) AS PersonalMedianCharge
    FROM (
        SELECT
            cust_id,
            inv_amount,
            ROW_NUMBER() OVER (PARTITION BY cust_id ORDER BY inv_amount) AS med_rn,
            COUNT(*) OVER (PARTITION BY cust_id) AS cnt
        FROM BillHistory
    ) x
    WHERE med_rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    GROUP BY cust_id
),
FeatureSet AS (
    SELECT
        b.cust_id,
        b.Bill_Date,
        b.inv_amount,
        m.PersonalMedianCharge,
        CASE WHEN m.PersonalMedianCharge > 0
             THEN (b.inv_amount - m.PersonalMedianCharge) / m.PersonalMedianCharge * 100.0
             ELSE NULL END AS BillIncreasePct,
        b.CreditScore,
        DATEDIFF(DAY, b.FlowStart, b.Bill_Date) AS TenureDays
    FROM BillHistory b
    INNER JOIN MedianPerCust m ON b.cust_id = m.cust_id
    WHERE m.PersonalMedianCharge IS NOT NULL
      AND b.CreditScore IS NOT NULL AND b.CreditScore != 0
),
CallsByCustomer AS (
    SELECT DISTINCT CustID AS cust_id, CallDate
    FROM vw_Care_CustomerContact
)
SELECT
    f.*,
    CASE WHEN EXISTS (
        SELECT 1 FROM CallsByCustomer c
        WHERE c.cust_id = f.cust_id
          AND c.CallDate BETWEEN f.Bill_Date AND DATEADD(DAY, 14, f.Bill_Date)
    ) THEN 1 ELSE 0 END AS CalledWithin14Days
INTO dbo.Task7_FeatureSet
FROM FeatureSet f



SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vw_Salesforce_Autopay'
ORDER BY ORDINAL_POSITION



SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vw_Salesforce_BillingAccount'
ORDER BY ORDINAL_POSITION


SELECT DISTINCT Action FROM vw_Salesforce_Autopay



-- STEP 1: Identify card-change autopay removals via call.summary keyword search
-- Join Care_CallAI -> ContactID -> vw_Care_CustomerContact -> CustID (same pattern as Task 7)
-- Then check which of those customers did NOT re-enroll within 60 days

WITH CardChangeCalls AS (
    SELECT DISTINCT
        cc.CustID AS cust_id,
        cc.CallDate
    FROM dbo.Care_CallAI ca
    INNER JOIN vw_Care_CustomerContact cc
        ON ca.ContactID = cc.ContactID
    WHERE ca.[call.summary] LIKE '%expired card%'
       OR ca.[call.summary] LIKE '%lost%card%'
       OR ca.[call.summary] LIKE '%cancel%card%'
       OR ca.[call.summary] LIKE '%new card%'
       OR ca.[call.summary] LIKE '%update%card%'
       OR ca.[call.summary] LIKE '%update%payment method%'
),
AutopayRemovals AS (
    SELECT
        ba.CustID AS cust_id,
        a.Created AS RemovalDate
    FROM vw_Salesforce_Autopay a
    INNER JOIN vw_Salesforce_BillingAccount ba
        ON a.AccountID = ba.ID
    WHERE a.Action = 'Remove'
),
CardChangeRemovals AS (
    SELECT DISTINCT
        r.cust_id,
        r.RemovalDate
    FROM AutopayRemovals r
    INNER JOIN CardChangeCalls c
        ON r.cust_id = c.cust_id
        AND c.CallDate BETWEEN DATEADD(DAY, -7, r.RemovalDate) AND DATEADD(DAY, 7, r.RemovalDate)
),
ReEnrollCheck AS (
    SELECT
        r.cust_id,
        r.RemovalDate,
        CASE WHEN EXISTS (
            SELECT 1 FROM vw_Salesforce_Autopay a2
            INNER JOIN vw_Salesforce_BillingAccount ba2 ON a2.AccountID = ba2.ID
            WHERE ba2.CustID = r.cust_id
              AND a2.Action = 'Add'
              AND a2.Created BETWEEN r.RemovalDate AND DATEADD(DAY, 60, r.RemovalDate)
        ) THEN 1 ELSE 0 END AS ReEnrolledWithin60Days
    FROM CardChangeRemovals r
)
SELECT
    rc.cust_id,
    rc.RemovalDate,
    c.FlowEnd,      -- NULL = still active
    c.Status,
    c.Waiver        -- 'Autopay' = currently on autopay
FROM ReEnrollCheck rc
INNER JOIN iSigma_Customer_Master c ON rc.cust_id = c.cust_id
WHERE rc.ReEnrolledWithin60Days = 0



SELECT
    CASE WHEN c.FlowEnd IS NOT NULL THEN 'Churned' ELSE 'Still Active' END AS CustomerStatus,
    COUNT(*) AS CustomerCount
FROM ReEnrollCheck rc
INNER JOIN iSigma_Customer_Master c ON rc.cust_id = c.cust_id
WHERE rc.ReEnrolledWithin60Days = 0
GROUP BY CASE WHEN c.FlowEnd IS NOT NULL THEN 'Churned' ELSE 'Still Active' END


WITH CardChangeCalls AS (
    SELECT DISTINCT
        cc.CustID AS cust_id,
        cc.CallDate
    FROM dbo.Care_CallAI ca
    INNER JOIN vw_Care_CustomerContact cc
        ON ca.ContactID = cc.ContactID
    WHERE ca.[call.summary] LIKE '%expired card%'
       OR ca.[call.summary] LIKE '%lost%card%'
       OR ca.[call.summary] LIKE '%cancel%card%'
       OR ca.[call.summary] LIKE '%new card%'
       OR ca.[call.summary] LIKE '%update%card%'
       OR ca.[call.summary] LIKE '%update%payment method%'
),
AutopayRemovals AS (
    SELECT
        ba.CustID AS cust_id,
        a.Created AS RemovalDate
    FROM vw_Salesforce_Autopay a
    INNER JOIN vw_Salesforce_BillingAccount ba
        ON a.AccountID = ba.ID
    WHERE a.Action = 'Remove'
),
CardChangeRemovals AS (
    SELECT DISTINCT
        r.cust_id,
        r.RemovalDate
    FROM AutopayRemovals r
    INNER JOIN CardChangeCalls c
        ON r.cust_id = c.cust_id
        AND c.CallDate BETWEEN DATEADD(DAY, -7, r.RemovalDate) AND DATEADD(DAY, 7, r.RemovalDate)
),
ReEnrollCheck AS (
    SELECT
        r.cust_id,
        r.RemovalDate,
        CASE WHEN EXISTS (
            SELECT 1 FROM vw_Salesforce_Autopay a2
            INNER JOIN vw_Salesforce_BillingAccount ba2 ON a2.AccountID = ba2.ID
            WHERE ba2.CustID = r.cust_id
              AND a2.Action = 'Add'
              AND a2.Created BETWEEN r.RemovalDate AND DATEADD(DAY, 60, r.RemovalDate)
        ) THEN 1 ELSE 0 END AS ReEnrolledWithin60Days
    FROM CardChangeRemovals r
)
SELECT
    CASE WHEN c.FlowEnd IS NOT NULL THEN 'Churned' ELSE 'Still Active' END AS CustomerStatus,
    COUNT(*) AS CustomerCount
FROM ReEnrollCheck rc
INNER JOIN iSigma_Customer_Master c ON rc.cust_id = c.cust_id
WHERE rc.ReEnrolledWithin60Days = 0
GROUP BY CASE WHEN c.FlowEnd IS NOT NULL THEN 'Churned' ELSE 'Still Active' END



WITH CardChangeCalls AS (
    SELECT DISTINCT
        cc.CustID AS cust_id,
        cc.CallDate
    FROM dbo.Care_CallAI ca
    INNER JOIN vw_Care_CustomerContact cc
        ON ca.ContactID = cc.ContactID
    WHERE ca.[call.summary] LIKE '%expired card%'
       OR ca.[call.summary] LIKE '%lost%card%'
       OR ca.[call.summary] LIKE '%cancel%card%'
       OR ca.[call.summary] LIKE '%new card%'
       OR ca.[call.summary] LIKE '%update%card%'
       OR ca.[call.summary] LIKE '%update%payment method%'
),
AutopayRemovals AS (
    SELECT
        ba.CustID AS cust_id,
        a.Created AS RemovalDate
    FROM vw_Salesforce_Autopay a
    INNER JOIN vw_Salesforce_BillingAccount ba
        ON a.AccountID = ba.ID
    WHERE a.Action = 'Remove'
),
CardChangeRemovals AS (
    SELECT DISTINCT
        r.cust_id,
        r.RemovalDate
    FROM AutopayRemovals r
    INNER JOIN CardChangeCalls c
        ON r.cust_id = c.cust_id
        AND c.CallDate BETWEEN DATEADD(DAY, -7, r.RemovalDate) AND DATEADD(DAY, 7, r.RemovalDate)
),
ReEnrollCheck AS (
    SELECT
        r.cust_id,
        r.RemovalDate,
        CASE WHEN EXISTS (
            SELECT 1 FROM vw_Salesforce_Autopay a2
            INNER JOIN vw_Salesforce_BillingAccount ba2 ON a2.AccountID = ba2.ID
            WHERE ba2.CustID = r.cust_id
              AND a2.Action = 'Add'
              AND a2.Created BETWEEN r.RemovalDate AND DATEADD(DAY, 60, r.RemovalDate)
        ) THEN 1 ELSE 0 END AS ReEnrolledWithin60Days
    FROM CardChangeRemovals r
)
SELECT
    rc.cust_id,
    rc.RemovalDate,
    c.FlowEnd,
    b.PastDue,
    b.TotalDue,
    b.Aging_1_30,
    b.Aging_31_60,
    b.Aging_61_90,
    b.Aging_91_120,
    b.Aging_120_plus
FROM ReEnrollCheck rc
INNER JOIN iSigma_Customer_Master c ON rc.cust_id = c.cust_id
INNER JOIN iSigma_Customer_Master b ON rc.cust_id = b.cust_id  -- aging fields live on customer master (rows 97-105 from earlier schema pull)
WHERE rc.ReEnrolledWithin60Days = 0
  AND c.FlowEnd IS NOT NULL


SELECT
    rc.cust_id,
    rc.RemovalDate,
    c.FlowEnd,
    c.PastDue,
    c.TotalDue,
    c.Aging_1_30,
    c.Aging_31_60,
    c.Aging_61_90,
    c.Aging_91_120,
    c.Aging_120_plus
FROM ReEnrollCheck rc
INNER JOIN iSigma_Customer_Master c ON rc.cust_id = c.cust_id
WHERE rc.ReEnrolledWithin60Days = 0
  AND c.FlowEnd IS NOT NULL




WITH CardChangeCalls AS (
    SELECT DISTINCT
        cc.CustID AS cust_id,
        cc.CallDate
    FROM dbo.Care_CallAI ca
    INNER JOIN vw_Care_CustomerContact cc
        ON ca.ContactID = cc.ContactID
    WHERE ca.[call.summary] LIKE '%expired card%'
       OR ca.[call.summary] LIKE '%lost%card%'
       OR ca.[call.summary] LIKE '%cancel%card%'
       OR ca.[call.summary] LIKE '%new card%'
       OR ca.[call.summary] LIKE '%update%card%'
       OR ca.[call.summary] LIKE '%update%payment method%'
),
AutopayRemovals AS (
    SELECT
        ba.CustID AS cust_id,
        a.Created AS RemovalDate
    FROM vw_Salesforce_Autopay a
    INNER JOIN vw_Salesforce_BillingAccount ba
        ON a.AccountID = ba.ID
    WHERE a.Action = 'Remove'
),
CardChangeRemovals AS (
    SELECT DISTINCT
        r.cust_id,
        r.RemovalDate
    FROM AutopayRemovals r
    INNER JOIN CardChangeCalls c
        ON r.cust_id = c.cust_id
        AND c.CallDate BETWEEN DATEADD(DAY, -7, r.RemovalDate) AND DATEADD(DAY, 7, r.RemovalDate)
),
ReEnrollCheck AS (
    SELECT
        r.cust_id,
        r.RemovalDate,
        CASE WHEN EXISTS (
            SELECT 1 FROM vw_Salesforce_Autopay a2
            INNER JOIN vw_Salesforce_BillingAccount ba2 ON a2.AccountID = ba2.ID
            WHERE ba2.CustID = r.cust_id
              AND a2.Action = 'Add'
              AND a2.Created BETWEEN r.RemovalDate AND DATEADD(DAY, 60, r.RemovalDate)
        ) THEN 1 ELSE 0 END AS ReEnrolledWithin60Days
    FROM CardChangeRemovals r
),
ChurnedWithBalance AS (
    SELECT
        rc.cust_id,
        c.PastDue,
        c.TotalDue
    FROM ReEnrollCheck rc
    INNER JOIN iSigma_Customer_Master c ON rc.cust_id = c.cust_id
    WHERE rc.ReEnrolledWithin60Days = 0
      AND c.FlowEnd IS NOT NULL
)
SELECT
    COUNT(*) AS TotalChurned,
    SUM(CASE WHEN PastDue > 0 THEN 1 ELSE 0 END) AS LeftWithPastDue,
    SUM(PastDue) AS TotalPastDueAmount,
    SUM(TotalDue) AS TotalOwed,
    AVG(PastDue) AS AvgPastDuePerCustomer
FROM ChurnedWithBalance



-- STEP 1: Baseline churn rate for a comparable population
-- Compare: customers active around the same time as our card-change removals,
-- checked ~60+ days later, same as our test group

WITH CardChangeRemovalDates AS (
    -- Reuse: just the removal dates from our existing analysis, to know the comparison window
    SELECT MIN(RemovalDate) AS MinDate, MAX(RemovalDate) AS MaxDate
    FROM (
        SELECT a.Created AS RemovalDate
        FROM vw_Salesforce_Autopay a
        WHERE a.Action = 'Remove'
    ) x
),
BaselinePopulation AS (
    SELECT
        c.cust_id,
        c.FlowStart,
        c.FlowEnd
    FROM iSigma_Customer_Master c
    WHERE c.Market = 'Texas'
      AND c.CustomerType = 'Residential'
      AND c.FlowStart < DATEADD(DAY, -60, GETDATE())  -- must have had at least 60 days to churn
)
SELECT
    COUNT(*) AS TotalBaselineCustomers,
    SUM(CASE WHEN FlowEnd IS NOT NULL THEN 1 ELSE 0 END) AS ChurnedCount,
    CAST(SUM(CASE WHEN FlowEnd IS NOT NULL THEN 1 ELSE 0 END) AS FLOAT)
        / COUNT(*) * 100.0 AS ChurnRatePct
FROM BaselinePopulation
