-- ============================================================
-- INTERVAL FORECAST REBUILD — ENG vs. SPA Aggregation
-- Follow-up task from Jonathan (8/19 meeting): "Backtest and compare
-- forecast accuracy at 15-minute versus 30-minute intervals for
-- English and Spanish frontline Texas queues, prepare side-by-side
-- results for review with Lou."
--
-- Also implements Jonathan's earlier scope redirect: aggregate to
-- ENG vs. SPA level only (not per-queue), filtered to
-- CallType IN ('Inbound', 'Transfer') only.
-- ============================================================

-- ------------------------------------------------------------
-- CLEANUP: drop leftover temp tables from any previous run
-- ------------------------------------------------------------
IF OBJECT_ID('tempdb..#IVRRaw') IS NOT NULL DROP TABLE #IVRRaw;
IF OBJECT_ID('tempdb..#IVR15min') IS NOT NULL DROP TABLE #IVR15min;
IF OBJECT_ID('tempdb..#IVR30min') IS NOT NULL DROP TABLE #IVR30min;

-- ------------------------------------------------------------
-- STEP 0: VERIFY COLUMN NAMES FIRST — run this by itself before
-- the rest of the script. The column names below (CallType,
-- QueueName, CallDateTime) are best guesses based on prior work,
-- NOT confirmed for this specific pull. Check the real names here
-- first, same lesson learned repeatedly on this project.
-- ------------------------------------------------------------
SELECT COLUMN_NAME, DATA_TYPE
FROM Analytics_ConstellationWH.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'IVR'
ORDER BY ORDINAL_POSITION;

-- Plain English: this lists every real column name in dbo.IVR.
-- Compare against the guessed names used below (CallType,
-- QueueName, CallDateTime) and fix any that don't match before
-- running Step 1 onward.


-- ------------------------------------------------------------
-- STEP 1: Pull raw call-level records for the 17 confirmed Texas
-- South Care queues, filtered to Inbound/Transfer only (excludes
-- outbound-campaign-driven queues per Jonathan's redirect), tagged
-- with a language flag derived from the queue name.
--
-- NOTE: the language tag assumes Spanish queues are prefixed
-- "SPA_" (confirmed on one real queue name seen: "SPA_OTC_
-- Outbound_FCC_Consent_Yes_Active") and everything else in the
-- confirmed 17-queue list is English. VERIFY this pattern holds
-- across all 17 real queue names before trusting the aggregation —
-- if any English queue also happens to start with "SPA_" for an
-- unrelated reason, or a Spanish queue doesn't use that prefix,
-- this tagging will be wrong.
-- ------------------------------------------------------------
SELECT
      QueueName
    , CallDateTime
    , CallType
    , CASE
          WHEN QueueName LIKE 'SPA%' THEN 'SPA'
          ELSE 'ENG'
      END AS Language
INTO #IVRRaw
FROM Analytics_ConstellationWH.dbo.IVR
WHERE CallType IN ('Inbound', 'Transfer')
    AND QueueName IN (
        -- Paste the 17 confirmed real queue names here, exactly as
        -- they appear in dbo.IVR (minor naming/spacing differences
        -- were already reconciled during the original validation —
        -- reuse that confirmed list rather than re-guessing).
        'PLACEHOLDER_QUEUE_1',
        'PLACEHOLDER_QUEUE_2'
        -- ... remaining confirmed queue names
    );

-- Plain English: pulls every individual Inbound/Transfer call
-- record for the confirmed queue list, and tags each one ENG or
-- SPA based on the queue name pattern.


-- ------------------------------------------------------------
-- STEP 2: Aggregate to 15-minute buckets, by language only (not
-- per-queue) — this is the core of Jonathan's redirect.
-- ------------------------------------------------------------
SELECT
      Language
    , DATEADD(MINUTE, (DATEDIFF(MINUTE, 0, CallDateTime) / 15) * 15, 0) AS Interval15Min
    , COUNT(*) AS CallCount
INTO #IVR15min
FROM #IVRRaw
GROUP BY
      Language
    , DATEADD(MINUTE, (DATEDIFF(MINUTE, 0, CallDateTime) / 15) * 15, 0);

-- Plain English: rounds each call's timestamp down to the nearest
-- 15-minute mark, then counts how many ENG calls and how many SPA
-- calls happened in each 15-minute window.


-- ------------------------------------------------------------
-- STEP 3: Aggregate to 30-minute buckets, same logic, for the
-- side-by-side comparison.
-- ------------------------------------------------------------
SELECT
      Language
    , DATEADD(MINUTE, (DATEDIFF(MINUTE, 0, CallDateTime) / 30) * 30, 0) AS Interval30Min
    , COUNT(*) AS CallCount
INTO #IVR30min
FROM #IVRRaw
GROUP BY
      Language
    , DATEADD(MINUTE, (DATEDIFF(MINUTE, 0, CallDateTime) / 30) * 30, 0);


-- ------------------------------------------------------------
-- STEP 4: Final export — run each of these separately and export
-- both (SSMS "Save Results As CSV", add header row, plain UTF-8,
-- no BOM — same as every other pull on this project).
-- ------------------------------------------------------------
SELECT * FROM #IVR15min ORDER BY Language, Interval15Min ASC;
-- SELECT * FROM #IVR30min ORDER BY Language, Interval30Min ASC;  -- run this one separately

-- ------------------------------------------------------------
-- NEXT STEP AFTER EXPORTING BOTH:
-- Feed both CSVs into the same backtest pipeline used for the
-- original per-queue analysis (zero-fill missing intervals →
-- day-of-week/time-slot baseline → leave-one-out backtest), run
-- separately for ENG and SPA, at both 15-min and 30-min. That
-- gives the real side-by-side comparison Jonathan and Lou asked
-- for, at the new aggregation level.
-- ------------------------------------------------------------
