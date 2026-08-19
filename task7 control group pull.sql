-- ============================================================
-- TASK 7: Control Group Pull — Active (non-switched) Customers
-- Purpose: pull BAT_SMT usage for customers who did NOT switch,
-- matched on the same basic profile as the SwitchBeforeBillDue
-- sample, so the within-cycle flag logic can be tested against
-- a real false-positive rate (not just known switchers).
-- ============================================================

-- CONNECTION NOTE: three-part naming used throughout, same as the
-- switcher pull, so this runs regardless of which warehouse the
-- connection defaults to.

-- ------------------------------------------------------------
-- CLEANUP: drop leftover temp tables from any previous run
-- ------------------------------------------------------------
IF OBJECT_ID('tempdb..#ActiveCustomers') IS NOT NULL DROP TABLE #ActiveCustomers;
IF OBJECT_ID('tempdb..#ControlSample') IS NOT NULL DROP TABLE #ControlSample;
IF OBJECT_ID('tempdb..#ControlBatSmt') IS NOT NULL DROP TABLE #ControlBatSmt;

-- ------------------------------------------------------------
-- STEP 1: Identify currently-ACTIVE residential Texas customers
-- (i.e. the opposite of the switcher pull -- Status is NOT 'I').
-- NOTE: 'A' is a guess for the active status code -- verify
-- against real distinct values before trusting this filter.
-- ------------------------------------------------------------
SELECT DISTINCT
      CM.cust_id
    , CM.Instance
    , CM.CustomerType
    , CM.Market
    , CM.Status
INTO #ActiveCustomers
FROM Analytics_ConstellationWH.dbo.iSigma_Customer_Master AS CM
WHERE CM.Status <> 'I'
    AND CM.CustomerType = 'Residential'
    AND CM.Market = 'Texas'
    AND CM.Warning IS NULL;

-- Plain English: this is the mirror image of the switcher query --
-- instead of customers who left, this pulls customers who are
-- still active, using the same Residential/Texas/no-Warning
-- filters so the comparison is apples-to-apples.


-- ------------------------------------------------------------
-- STEP 2: Verify the Status filter caught the right thing before
-- trusting it -- run this SEPARATELY first if unsure:
-- SELECT DISTINCT Status FROM Analytics_ConstellationWH.dbo.iSigma_Customer_Master;
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- STEP 3: Sample 200 active customers at random (not most-recent,
-- since there's no FlowEnd to sort by for active accounts)
-- ------------------------------------------------------------
SELECT TOP 200
      cust_id
    , Instance
INTO #ControlSample
FROM #ActiveCustomers
ORDER BY NEWID();

-- Plain English: NEWID() shuffles the list randomly, so this grabs
-- 200 random active customers rather than always the same ones.


-- ------------------------------------------------------------
-- STEP 4: Pull BAT_SMT for the control sample. If this comes back
-- EMPTY, that's the answer to open question #2 -- BAT_SMT does
-- NOT cover active customers, only those who've already left.
-- ------------------------------------------------------------
SELECT
      S.cust_id
    , S.Instance
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
INTO #ControlBatSmt
FROM #ControlSample AS S
INNER JOIN Care_BillAnalyzerTool_WH.dbo.BAT_SMT AS SMT
    ON S.cust_id = SMT.Cust_id
    AND S.Instance = SMT.Instance
ORDER BY S.cust_id, SMT.PROFILE_DATE ASC;

-- Plain English: same shape as the switcher pull, just against
-- active customers instead. days_into_cycle is calculated the
-- same way so the Python script can run unchanged against this
-- file, just swapped in as the control group.


-- ------------------------------------------------------------
-- STEP 5: Final output -- export this exactly like the switcher
-- pull (SSMS "Save Results As CSV", add header row manually,
-- save as plain UTF-8, no BOM)
-- ------------------------------------------------------------
SELECT *
FROM #ControlBatSmt
ORDER BY cust_id, PROFILE_DATE ASC;

-- ------------------------------------------------------------
-- IF THIS RETURNS ZERO ROWS:
-- That's a real, useful answer -- it means BAT_SMT only covers
-- customers who've already left, and this whole approach can
-- only ever be a BACKTESTING tool, not a live/deployed alert,
-- unless Andres can point to a different table or expand BAT_SMT
-- coverage. Worth flagging to Jonathan either way.
-- ------------------------------------------------------------
