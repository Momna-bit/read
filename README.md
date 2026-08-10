	
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



-- STEP 1 (corrected): Baseline 60-day churn rate for a comparable population
-- Pick a reference date range matching the card-change removal window,
-- take customers active on those dates, check churn ~60 days later

WITH ReferenceDates AS (
    SELECT DISTINCT a.Created AS RefDate
    FROM vw_Salesforce_Autopay a
    WHERE a.Action = 'Remove'
      AND a.Created BETWEEN '2026-01-01' AND '2026-07-01'  -- adjust to match your actual removal window
),
BaselineSample AS (
    SELECT
        c.cust_id,
        r.RefDate,
        c.FlowStart,
        c.FlowEnd
    FROM ReferenceDates r
    INNER JOIN iSigma_Customer_Master c
        ON c.Market = 'Texas'
       AND c.CustomerType = 'Residential'
       AND c.FlowStart < r.RefDate  -- must have been an existing customer as of that date
       AND (c.FlowEnd IS NULL OR c.FlowEnd > r.RefDate)  -- must have been active on that date
)
SELECT
    COUNT(*) AS TotalBaselineCustomers,
    SUM(CASE WHEN FlowEnd IS NOT NULL AND FlowEnd <= DATEADD(DAY, 60, RefDate) THEN 1 ELSE 0 END) AS ChurnedWithin60Days,
    CAST(SUM(CASE WHEN FlowEnd IS NOT NULL AND FlowEnd <= DATEADD(DAY, 60, RefDate) THEN 1 ELSE 0 END) AS FLOAT)
        / COUNT(*) * 100.0 AS ChurnRatePct
FROM BaselineSample



SELECT
    COUNT_BIG(*) AS TotalBaselineCustomers,
    SUM(CAST(CASE WHEN FlowEnd IS NOT NULL AND FlowEnd <= DATEADD(DAY, 60, RefDate) THEN 1 ELSE 0 END AS BIGINT)) AS ChurnedWithin60Days,
    CAST(SUM(CAST(CASE WHEN FlowEnd IS NOT NULL AND FlowEnd <= DATEADD(DAY, 60, RefDate) THEN 1 ELSE 0 END AS BIGINT)) AS FLOAT)
        / COUNT_BIG(*) * 100.0 AS ChurnRatePct
FROM BaselineSample




-- STEP 1 (fixed): Baseline 60-day churn rate using a single representative reference date
-- Avoids the multiplied cross-join across every distinct removal date

DECLARE @RefDate DATE = '2026-04-01';  -- pick a midpoint date within your removal window

WITH BaselineSample AS (
    SELECT
        c.cust_id,
        c.FlowEnd
    FROM iSigma_Customer_Master c
    WHERE c.Market = 'Texas'
      AND c.CustomerType = 'Residential'
      AND c.FlowStart < @RefDate
      AND (c.FlowEnd IS NULL OR c.FlowEnd > @RefDate)
)
SELECT
    COUNT_BIG(*) AS TotalBaselineCustomers,
    SUM(CAST(CASE WHEN FlowEnd IS NOT NULL AND FlowEnd <= DATEADD(DAY, 60, @RefDate) THEN 1 ELSE 0 END AS BIGINT)) AS ChurnedWithin60Days,
    CAST(SUM(CAST(CASE WHEN FlowEnd IS NOT NULL AND FlowEnd <= DATEADD(DAY, 60, @RefDate) THEN 1 ELSE 0 END AS BIGINT)) AS FLOAT)
        / COUNT_BIG(*) * 100.0 AS ChurnRatePct
FROM BaselineSample




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
NonReEnrolled AS (
    SELECT
        rc.cust_id,
        rc.RemovalDate,
        c.FlowEnd,
        c.CreditScore,
        DATEDIFF(DAY, c.FlowStart, rc.RemovalDate) AS TenureDaysAtRemoval
    FROM ReEnrollCheck rc
    INNER JOIN iSigma_Customer_Master c ON rc.cust_id = c.cust_id
    WHERE rc.ReEnrolledWithin60Days = 0
)
SELECT
    CASE WHEN FlowEnd IS NOT NULL THEN 'Churned' ELSE 'Still Active' END AS CustomerStatus,
    COUNT(*) AS CustomerCount,
    AVG(CAST(CreditScore AS FLOAT)) AS AvgCreditScore,
    AVG(CAST(TenureDaysAtRemoval AS FLOAT)) AS AvgTenureDays
FROM NonReEnrolled
WHERE CreditScore IS NOT NULL AND CreditScore != 0
GROUP BY CASE WHEN FlowEnd IS NOT NULL THEN 'Churned' ELSE 'Still Active' END




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
)
SELECT
    MIN(RemovalDate) AS EarliestRemoval,
    MAX(RemovalDate) AS LatestRemoval,
    COUNT(*) AS TotalRemovals
FROM CardChangeRemovals





-- ============================================================================
-- STEP 1: 12-month backtest — forecasted calls vs. actual calls, day by day
-- Covers the trailing 12 months of real IVR data
-- ============================================================================

WITH BaselineCount AS (
    SELECT COUNT(*) AS BaselineCount
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND FlowStart < '2022-07-01'
        AND (FlowEnd IS NULL OR FlowEnd >= '2022-07-01')
),
ActiveDelta AS (
    SELECT CAST(FlowStart AS DATE) AS EventDate, 1 AS Delta
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential' AND FlowStart >= '2022-07-01'
    UNION ALL
    SELECT CAST(DATEADD(DAY, 1, FlowEnd) AS DATE) AS EventDate, -1 AS Delta
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential' AND FlowEnd >= '2022-07-01'
),
DailyDelta AS (SELECT EventDate, SUM(Delta) AS NetChange FROM ActiveDelta GROUP BY EventDate),

RecentRates AS (
    SELECT * FROM (VALUES
        (1, 0.000), (2, 6.703), (3, 5.254), (4, 4.826),
        (5, 4.279), (6, 4.668), (7, 1.875)
    ) AS t(DayNum, RecentRatePer1000)
),
SeasonalIndex AS (
    SELECT * FROM (VALUES
        (1, 1.107), (2, 1.214), (3, 1.049), (4, 0.931), (5, 0.928), (6, 0.955),
        (7, 1.074), (8, 1.085), (9, 1.059), (10, 0.935), (11, 0.848), (12, 0.802)
    ) AS t(MonthNum, SeasonalIdx)
),

Digits AS (SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)),
Numbers AS (SELECT (d1.n + d2.n*10 + d3.n*100) AS OffsetDay FROM Digits d1 CROSS JOIN Digits d2 CROSS JOIN Digits d3),
CheckCalendar AS (
    -- Trailing 12 months, ending yesterday (adjust end date as needed)
    SELECT DATEADD(DAY, -OffsetDay, CAST(DATEADD(DAY, -1, GETDATE()) AS DATE)) AS CallDay
    FROM Numbers WHERE OffsetDay < 365
),

ForecastActive AS (
    SELECT cc.CallDay,
        bc.BaselineCount + ISNULL((SELECT SUM(dd.NetChange) FROM DailyDelta dd WHERE dd.EventDate <= cc.CallDay), 0) AS ActiveCustomerCount
    FROM CheckCalendar cc CROSS JOIN BaselineCount bc
),

Forecasted AS (
    SELECT
        fa.CallDay,
        ROUND((rr.RecentRatePer1000 * si.SeasonalIdx / 1000.0) * fa.ActiveCustomerCount, 0) AS ForecastedCalls
    FROM ForecastActive fa
    JOIN RecentRates rr ON rr.DayNum = DATEPART(WEEKDAY, fa.CallDay)
    JOIN SeasonalIndex si ON si.MonthNum = MONTH(fa.CallDay)
),

Actual AS (
    SELECT CAST(CallDate AS DATE) AS CallDay, COUNT(*) AS ActualCalls
    FROM dbo.IVR
    WHERE Department = 'Care' AND CallType IN ('Inbound', 'Transfer') AND AgentTalkTime > 0
    GROUP BY CAST(CallDate AS DATE)
)

SELECT
    f.CallDay,
    DATENAME(WEEKDAY, f.CallDay) AS DayOfWeek,
    f.ForecastedCalls,
    a.ActualCalls,
    ROUND(100.0 * (a.ActualCalls - f.ForecastedCalls) / f.ForecastedCalls, 1) AS PctVariance,
    CASE WHEN ABS(100.0 * (a.ActualCalls - f.ForecastedCalls) / f.ForecastedCalls) > 15
        THEN 'INVESTIGATE' ELSE 'Within Range' END AS Flag
FROM Forecasted f
JOIN Actual a ON a.CallDay = f.CallDay
ORDER BY f.CallDay;




-- ============================================================================
-- STEP 2: Recalibrate day-of-week rates using the full 12-month actual history
-- Replaces the single-week RecentRates table with a real 12-month average
-- ============================================================================

WITH BaselineCount AS (
    SELECT COUNT(*) AS BaselineCount
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND FlowStart < '2022-07-01'
        AND (FlowEnd IS NULL OR FlowEnd >= '2022-07-01')
),
ActiveDelta AS (
    SELECT CAST(FlowStart AS DATE) AS EventDate, 1 AS Delta
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential' AND FlowStart >= '2022-07-01'
    UNION ALL
    SELECT CAST(DATEADD(DAY, 1, FlowEnd) AS DATE) AS EventDate, -1 AS Delta
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential' AND FlowEnd >= '2022-07-01'
),
DailyDelta AS (SELECT EventDate, SUM(Delta) AS NetChange FROM ActiveDelta GROUP BY EventDate),

Digits AS (SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)),
Numbers AS (SELECT (d1.n + d2.n*10 + d3.n*100) AS OffsetDay FROM Digits d1 CROSS JOIN Digits d2 CROSS JOIN Digits d3),
HistoryCalendar AS (
    SELECT DATEADD(DAY, -OffsetDay, CAST(DATEADD(DAY, -1, GETDATE()) AS DATE)) AS CallDay
    FROM Numbers WHERE OffsetDay < 365
),

ActiveOnDay AS (
    SELECT hc.CallDay,
        bc.BaselineCount + ISNULL((SELECT SUM(dd.NetChange) FROM DailyDelta dd WHERE dd.EventDate <= hc.CallDay), 0) AS ActiveCustomerCount
    FROM HistoryCalendar hc CROSS JOIN BaselineCount bc
),

ActualCalls AS (
    SELECT CAST(CallDate AS DATE) AS CallDay, COUNT(*) AS ActualCalls
    FROM dbo.IVR
    WHERE Department = 'Care' AND CallType IN ('Inbound', 'Transfer') AND AgentTalkTime > 0
    GROUP BY CAST(CallDate AS DATE)
),

DailyRate AS (
    SELECT
        ao.CallDay,
        DATEPART(WEEKDAY, ao.CallDay) AS DayNum,
        DATENAME(WEEKDAY, ao.CallDay) AS DayName,
        ac.ActualCalls,
        ao.ActiveCustomerCount,
        (CAST(ac.ActualCalls AS FLOAT) / ao.ActiveCustomerCount) * 1000.0 AS RatePer1000
    FROM ActiveOnDay ao
    INNER JOIN ActualCalls ac ON ac.CallDay = ao.CallDay
)

SELECT
    DayNum,
    DayName,
    COUNT(*) AS DaysObserved,
    ROUND(AVG(RatePer1000), 3) AS AvgRatePer1000,
    ROUND(MIN(RatePer1000), 3) AS MinRatePer1000,
    ROUND(MAX(RatePer1000), 3) AS MaxRatePer1000
FROM DailyRate
GROUP BY DayNum, DayName
ORDER BY DayNum;




WITH BaselineCount AS (
    SELECT COUNT(*) AS BaselineCount
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND FlowStart < '2022-07-01'
        AND (FlowEnd IS NULL OR FlowEnd >= '2022-07-01')
),
ActiveDelta AS (
    SELECT CAST(FlowStart AS DATE) AS EventDate, 1 AS Delta
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential' AND FlowStart >= '2022-07-01'
    UNION ALL
    SELECT CAST(DATEADD(DAY, 1, FlowEnd) AS DATE) AS EventDate, -1 AS Delta
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential' AND FlowEnd >= '2022-07-01'
),
DailyDelta AS (SELECT EventDate, SUM(Delta) AS NetChange FROM ActiveDelta GROUP BY EventDate),

RecentRates AS (
    SELECT * FROM (VALUES
        (1, 0.000),
        (2, 7.485),
        (3, 6.407),
        (4, 5.582),
        (5, 4.948),
        (6, 5.418),
        (7, 2.238)
    ) AS t(DayNum, RecentRatePer1000)
),
SeasonalIndex AS (
    SELECT * FROM (VALUES
        (1, 1.107), (2, 1.214), (3, 1.049), (4, 0.931), (5, 0.928), (6, 0.955),
        (7, 1.074), (8, 1.085), (9, 1.059), (10, 0.935), (11, 0.848), (12, 0.802)
    ) AS t(MonthNum, SeasonalIdx)
),

Digits AS (SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)),
Numbers AS (SELECT (d1.n + d2.n*10 + d3.n*100) AS OffsetDay FROM Digits d1 CROSS JOIN Digits d2 CROSS JOIN Digits d3),
CheckCalendar AS (
    SELECT DATEADD(DAY, -OffsetDay, CAST(DATEADD(DAY, -1, GETDATE()) AS DATE)) AS CallDay
    FROM Numbers WHERE OffsetDay < 365
),

ForecastActive AS (
    SELECT cc.CallDay,
        bc.BaselineCount + ISNULL((SELECT SUM(dd.NetChange) FROM DailyDelta dd WHERE dd.EventDate <= cc.CallDay), 0) AS ActiveCustomerCount
    FROM CheckCalendar cc CROSS JOIN BaselineCount bc
),

Forecasted AS (
    SELECT
        fa.CallDay,
        ROUND((rr.RecentRatePer1000 * si.SeasonalIdx / 1000.0) * fa.ActiveCustomerCount, 0) AS ForecastedCalls
    FROM ForecastActive fa
    JOIN RecentRates rr ON rr.DayNum = DATEPART(WEEKDAY, fa.CallDay)
    JOIN SeasonalIndex si ON si.MonthNum = MONTH(fa.CallDay)
),

Actual AS (
    SELECT CAST(CallDate AS DATE) AS CallDay, COUNT(*) AS ActualCalls
    FROM dbo.IVR
    WHERE Department = 'Care' AND CallType IN ('Inbound', 'Transfer') AND AgentTalkTime > 0
    GROUP BY CAST(CallDate AS DATE)
)

SELECT
    f.CallDay,
    DATENAME(WEEKDAY, f.CallDay) AS DayOfWeek,
    f.ForecastedCalls,
    a.ActualCalls,
    ROUND(100.0 * (a.ActualCalls - f.ForecastedCalls) / f.ForecastedCalls, 1) AS PctVariance,
    CASE WHEN ABS(100.0 * (a.ActualCalls - f.ForecastedCalls) / f.ForecastedCalls) > 15
        THEN 'INVESTIGATE' ELSE 'Within Range' END AS Flag
FROM Forecasted f
JOIN Actual a ON a.CallDay = f.CallDay
ORDER BY f.CallDay;



-- Compare estimated vs. actual active customer count for one specific date
DECLARE @CheckDate DATE = '2025-08-12';

-- Direct, ground-truth count
SELECT COUNT(*) AS TrueActiveCount
FROM iSigma_Customer_Master
WHERE Market = 'Texas' AND CustomerType = 'Residential'
  AND FlowStart <= @CheckDate
  AND (FlowEnd IS NULL OR FlowEnd > @CheckDate);




SELECT
    FORMAT(CAST(CallDate AS DATE), 'yyyy-MM') AS CallMonth,
    COUNT(*) AS TotalCalls
FROM dbo.IVR
WHERE Department = 'Care' AND CallType IN ('Inbound', 'Transfer') AND AgentTalkTime > 0
  AND CallDate >= DATEADD(MONTH, -13, GETDATE())
GROUP BY FORMAT(CAST(CallDate AS DATE), 'yyyy-MM')
ORDER BY CallMonth;



SeasonalIndex AS (
    SELECT * FROM (VALUES
        (1, 0.904),   -- January
        (2, 0.932),   -- February
        (3, 0.865),   -- March
        (4, 0.774),   -- April
        (5, 0.752),   -- May
        (6, 0.915),   -- June
        (7, 1.028),   -- July (averaged from two data points: 0.938 and 1.118)
        (8, 1.354),   -- August
        (9, 1.369),   -- September
        (10, 1.268),  -- October
        (11, 0.910),  -- November
        (12, 0.900)   -- December
    ) AS t(MonthNum, SeasonalIdx)
),
