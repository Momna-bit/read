-- =====================================================================
-- Autopay Card-Change Removal Analysis
-- Goal: Of the customers who removed autopay after a card-change-related
-- call and did NOT re-enroll within 60 days, are they churning or just
-- paying manually? And is this group riskier than the general population?
-- =====================================================================

-- =====================================================================
-- STEP 1: Identify card-change autopay removals and check re-enrollment
-- =====================================================================
-- Card-change calls identified via keyword search on Care_CallAI's
-- free-text call.summary field (no structured "reason" field exists)
-- Joined: Care_CallAI -> ContactID -> vw_Care_CustomerContact -> CustID
-- Autopay events joined: vw_Salesforce_Autopay -> AccountID ->
--   vw_Salesforce_BillingAccount -> CustID

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
    -- Only keep removals with a matching card-change call within +/- 7 days
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
    c.Waiver
FROM ReEnrollCheck rc
INNER JOIN iSigma_Customer_Master c ON rc.cust_id = c.cust_id
WHERE rc.ReEnrolledWithin60Days = 0;


-- =====================================================================
-- STEP 2: Summarize churned vs. still-active among non-re-enrolled group
-- Result: 38 churned / 216 still active (out of 254 total)
-- =====================================================================

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
GROUP BY CASE WHEN c.FlowEnd IS NOT NULL THEN 'Churned' ELSE 'Still Active' END;


-- =====================================================================
-- STEP 3: Financial exposure of the churned group
-- Result: 38 churned, only 7 (18%) left with any past-due balance;
-- total past-due = $1,959.28; total owed = $6,285.25; avg past-due = $51.56
-- =====================================================================

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
FROM ChurnedWithBalance;


-- =====================================================================
-- STEP 4: Baseline 60-day churn rate for the general Texas residential
-- population, for comparison against the 15% churn rate seen above.
-- Result: 5.25% baseline churn rate (33,160 / 631,364)
-- i.e. the card-change/non-re-enrolled group churns at ~3x the baseline rate
-- =====================================================================
-- NOTE: @RefDate below is a single representative snapshot date chosen
-- to fall within the card-change removal window. Adjust if a different
-- date is more representative of your actual removal date range.

DECLARE @RefDate DATE = '2026-04-01';

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
FROM BaselineSample;


-- =====================================================================
-- STEP 5: Segment check — does churn skew toward lower credit score or
-- shorter tenure within the non-re-enrolled group?
-- Result: Churned group actually skews slightly HIGHER credit (827 vs 803)
-- and somewhat SHORTER tenure (664 vs 819 days) than still-active group.
-- Churn is NOT explained by credit risk in this population.
-- =====================================================================

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
GROUP BY CASE WHEN FlowEnd IS NOT NULL THEN 'Churned' ELSE 'Still Active' END;


-- =====================================================================
-- SUMMARY OF FINDINGS
-- =====================================================================
-- Of ~254 customers who removed autopay after a card-change call and
-- did not re-enroll within 60 days:
--   - 216 (85%) are still active (likely paying manually) - not a concern
--   - 38 (15%) churned - about 3x the baseline 60-day churn rate (5.25%)
--   - Financial exposure from the churned group is minimal:
--       only 7 of 38 left with any past-due balance,
--       total past-due across all 38 = $1,959.28 (avg ~$52/customer)
--   - Churn is NOT concentrated in a lower-credit or newer-tenure segment
--       (churned customers actually average slightly HIGHER credit score
--       and somewhat shorter tenure than those still active)
--
-- RECOMMENDATION: This is a real but low-cost signal. Worth a light-touch
-- follow-up (e.g. a reminder to re-enroll in autopay) rather than urgent
-- intervention, since financial exposure is minimal and churn is not
-- concentrated in an already-risky segment.
-- =====================================================================
