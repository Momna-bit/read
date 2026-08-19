-- ============================================================
-- TASK 7: Pre-Bill Usage Alert — BAT_SMT Backtest Pull
-- Purpose: pull daily/hourly usage from BAT_SMT for customers
-- already confirmed as SwitchBeforeBillDue, so the trigger-day
-- logic (N days into cycle) can be backtested against a known,
-- real outcome.
-- ============================================================

-- ------------------------------------------------------------
-- STEP 1: Rebuild the validated CustomerAttrition classification
-- and pull out ONLY the SwitchBeforeBillDue segment into a temp
-- table. NOTE: this re-creates the shape of the original
-- validated query from the handoff description. Column names
-- (DNPBill, DNPSent, DNPDue, FlowEnd, etc.) should be re-verified
-- against INFORMATION_SCHEMA before running if this wasn't
-- copy-pasted directly from the original validated script --
-- don't trust this reconstruction blind.
-- ------------------------------------------------------------

SELECT
      CM.cust_id
    , CM.Instance
    , CFI.bill_no
    , CFI.create_date
    , B.Bill_date
    , CM.FlowEnd
    , CM.CustomerType
    , CM.Market
    , CASE
        WHEN CFI.create_date IS NULL THEN 'NoDebt'
        WHEN CFI.create_date < B.Bill_date AND CM.FlowEnd < B.Bill_date
            THEN 'SwitchBeforeBillDue'
        -- (remaining outcome branches — SwitchAfterBillDue, SwitchBeforeDNPDue,
        --  SwitchAfterDNPDue, DNP, MoveTransfer, FinalBillOnly, PostAttrition —
        --  omitted here since we only need SwitchBeforeBillDue for this pull;
        --  paste the full CASE block back in if you need the others too)
        ELSE 'Other'
    END AS Outcome
INTO #CustomerAttrition
FROM Analytics_ConstellationWH.dbo.iSigma_Customer_Master AS CM
INNER JOIN Analytics_ConstellationWH.dbo.iSigma_Customer_Fin_Invoices AS CFI
    ON CM.cust_id = CFI.cust_id
    AND CM.Instance = CFI.Instance
INNER JOIN Analytics_ConstellationWH.dbo.iSigma_Bill_Master AS B
    ON CFI.bill_no = B.Bill_No
    AND CFI.cust_id = B.cust_id
    AND CFI.Instance = B.Instance
WHERE CM.Status = 'I'
    AND CM.FlowEnd BETWEEN '2025-07-01' AND '2026-06-30'
    AND CM.CustomerType = 'Residential'
    AND CM.Market = 'Texas'
    AND CM.Warning IS NULL;

-- Plain English: this rebuilds the same customer-classification
-- logic already validated (22,985 customers / $8.68M debt), but
-- only pulls the SwitchBeforeBillDue outcome into a temp table so
-- we have a clean list of cust_id + Instance + FlowEnd to join
-- BAT_SMT against next.


-- ------------------------------------------------------------
-- STEP 2: Grab a manageable sample of SwitchBeforeBillDue
-- customers to backtest against, rather than pulling all
-- 22,985 at once. Adjust TOP N as needed once this runs clean.
-- ------------------------------------------------------------

SELECT TOP 200
      cust_id
    , Instance
    , bill_no
    , FlowEnd
INTO #SampleCustomers
FROM #CustomerAttrition
WHERE Outcome = 'SwitchBeforeBillDue'
ORDER BY FlowEnd DESC;

-- Plain English: takes the 200 most recent SwitchBeforeBillDue
-- customers as a first backtest batch. Small enough to eyeball
-- results customer-by-customer before scaling up.


-- ------------------------------------------------------------
-- STEP 3: Pull BAT_SMT rows for the sample customers, tagging
-- each usage day with how many days into its billing cycle it
-- falls (days_into_cycle) so we can later test different values
-- of N (trigger day) without re-querying.
-- ------------------------------------------------------------

SELECT
      S.cust_id
    , S.Instance
    , S.bill_no          AS sample_bill_no
    , S.FlowEnd
    , SMT.Premise_id
    , SMT.Bill_No
    , SMT.Bill_date
    , SMT.order_of_bill
    , SMT.order_of_bill_label
    , SMT.PROFILE_DATE
    , SMT.service_start
    , SMT.service_end
    , DATEDIFF(day, SMT.service_start, SMT.PROFILE_DATE) + 1 AS days_into_cycle
    , SMT.day_of_week
    , SMT.week_of_cycle
    , SMT.Total_Consumption
    , SMT.Hr_01, SMT.Hr_02, SMT.Hr_03, SMT.Hr_04, SMT.Hr_05, SMT.Hr_06
    , SMT.Hr_07, SMT.Hr_08, SMT.Hr_09, SMT.Hr_10, SMT.Hr_11, SMT.Hr_12
    , SMT.Hr_13, SMT.Hr_14, SMT.Hr_15, SMT.Hr_16, SMT.Hr_17, SMT.Hr_18
    , SMT.Hr_19, SMT.Hr_20, SMT.Hr_21, SMT.Hr_22, SMT.Hr_23, SMT.Hr_24
    , SMT.GenerationDate
INTO #BatSmtSample
FROM #SampleCustomers AS S
INNER JOIN dbo.BAT_SMT AS SMT
    ON S.cust_id = SMT.Cust_id
    AND S.Instance = SMT.Instance
ORDER BY S.cust_id, SMT.PROFILE_DATE ASC;

-- Plain English: for each of our 200 sample customers, this pulls
-- every daily usage row BAT_SMT has for them, and calculates
-- "days_into_cycle" — day 1, day 2, day 3... of that billing
-- period — so we can later ask "what did usage look like by day 5?
-- by day 10?" for each customer without recalculating each time.


-- ------------------------------------------------------------
-- STEP 4: Final output — one row per customer per cycle per day,
-- ready to load into Python for the actual trigger-logic testing
-- (comparing "Current" cycle pace vs. "Previous" cycle pace at
-- various values of N).
-- ------------------------------------------------------------

SELECT *
FROM #BatSmtSample
ORDER BY cust_id, PROFILE_DATE ASC;

-- Plain English: this is the export-ready result set. Save via
-- SSMS "Save Results As CSV" (no header row), add the header row
-- manually, save as plain UTF-8 (not UTF-8 BOM) before loading
-- into Python, per the usual workaround.


-- ------------------------------------------------------------
-- OPEN ITEMS — do not finalize interpretation until Andres replies:
-- 1. If order_of_bill_label supports more than "Previous"/"Current",
--    this query should be expanded to pull older cycles too for a
--    more robust historical-pace baseline.
-- 2. This pull only works for customers who ALREADY left
--    (FlowEnd is populated) — confirms backtesting is possible,
--    but does NOT tell us yet whether active customers are
--    covered for a future live alert.
-- 3. Total_Consumption / Hr_01-Hr_24 are pulled here as-is
--    (assumed daily, not cumulative). If Andres confirms these
--    are cumulative instead, Step 3/4 will need a LAG() diff
--    against the prior PROFILE_DATE per customer before these
--    numbers can be summed or compared meaningfully.
-- ------------------------------------------------------------
