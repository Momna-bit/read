	
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


SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vw_Salesforce_Autopay'
ORDER BY ORDINAL_POSITION;


-- WHY: Jonathan showed that the CreatedBy field on autopay actions tells us
-- the channel (an agent's ID = agent-initiated removal, "Integration API" =
-- customer did it themselves via the website/portal). This confirms that
-- split and gives us the actual volume by channel, over the last 6 months.

SELECT
    CASE 
        WHEN CreatedBy = 'Integration API' THEN 'Portal/Website'
        ELSE 'Agent'
    END AS RemovalChannel,
    COUNT(*) AS RemovalCount
FROM vw_Salesforce_Autopay
WHERE Remove = 1
    AND Created >= DATEADD(MONTH, -6, CAST(GETDATE() AS DATE))
GROUP BY CASE 
        WHEN CreatedBy = 'Integration API' THEN 'Portal/Website'
        ELSE 'Agent'
    END
ORDER BY RemovalCount DESC;


-- WHY: Jonathan's own exploration shows every removal tied to a named agent,
-- not "Integration API." Before concluding portal removals don't exist in
-- this data, let's check every distinct CreatedBy value directly.

SELECT DISTINCT CreatedBy
FROM vw_Salesforce_Autopay
WHERE Remove = 1
ORDER BY CreatedBy;


-- WHY: CreatedBy only stores User IDs, not channel labels directly.
-- The "Integration API" distinction Jonathan described must live in the
-- linked Salesforce User's name. Let's check if any distinct user name
-- looks like a system/portal account rather than a real agent.

SELECT DISTINCT U.Name, U.ID
FROM dbo.vw_Salesforce_Autopay A
INNER JOIN dbo.vw_Salesforce_User U ON U.ID = A.CreatedBy
WHERE A.Remove = 1
    AND (
        U.Name LIKE '%API%' 
        OR U.Name LIKE '%Integration%' 
        OR U.Name LIKE '%System%' 
        OR U.Name LIKE '%Portal%'
        OR U.Name LIKE '%Website%'
    );



-- WHY: We now know "Integration API" (portal/website channel) has a specific
-- User ID: 0054T000001dhK1QAI. This query does the real portal-vs-agent
-- split, joining through the User table correctly this time.

SELECT
    CASE 
        WHEN A.CreatedBy = '0054T000001dhK1QAI' THEN 'Portal/Website'
        ELSE 'Agent'
    END AS RemovalChannel,
    COUNT(*) AS RemovalCount
FROM dbo.vw_Salesforce_Autopay A
WHERE A.Remove = 1
    AND A.Created >= DATEADD(MONTH, -6, CAST(GETDATE() AS DATE))
GROUP BY CASE 
        WHEN A.CreatedBy = '0054T000001dhK1QAI' THEN 'Portal/Website'
        ELSE 'Agent'
    END
ORDER BY RemovalCount DESC;


-- WHY: To check whether portal-channel autopay removals follow the same
-- "close to bill due date" timing pattern already found for removals overall,
-- we need to connect the Salesforce AccountID on each removal to the
-- customer's actual billing record (cust_id) in iSigma. Let's confirm
-- that join path exists before building the timing analysis.

SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vw_Salesforce_BillingAccount'
ORDER BY ORDINAL_POSITION;



-- ============================================================================
-- WHY: We found 78% of autopay removals happen silently via the portal, with
-- no call to explain the reason. Since we can't ask "why" for those, this
-- checks something we CAN measure without call data: does the same timing
-- pattern (removals clustering near the bill due date) hold for portal
-- removals the same way it did for removals overall?
--
-- HOW: For each removal, find that customer's closest bill due date (before
-- or after the removal), then check what share of removals in each channel
-- happened within two weeks of that due date.
-- ============================================================================

WITH Removals AS (
    SELECT
        A.AccountID,
        A.Created AS RemovalDate,
        CASE WHEN A.CreatedBy = '0054T000001dhK1QAI' THEN 'Portal/Website' ELSE 'Agent' END AS RemovalChannel
    FROM dbo.vw_Salesforce_Autopay A
    WHERE A.Remove = 1
        AND A.Created >= DATEADD(MONTH, -6, CAST(GETDATE() AS DATE))
),

RemovalsWithCustID AS (
    SELECT
        r.AccountID,
        r.RemovalDate,
        r.RemovalChannel,
        b.CustID
    FROM Removals r
    JOIN dbo.vw_Salesforce_BillingAccount b ON b.ID = r.AccountID
),

RankedBills AS (
    -- For each removal, rank that customer's bills by closeness to the removal date
    SELECT
        rc.AccountID,
        rc.RemovalDate,
        rc.RemovalChannel,
        bm.Due_Date,
        ABS(DATEDIFF(DAY, rc.RemovalDate, bm.Due_Date)) AS DaysFromDueDate,
        ROW_NUMBER() OVER (
            PARTITION BY rc.AccountID, rc.RemovalDate 
            ORDER BY ABS(DATEDIFF(DAY, rc.RemovalDate, bm.Due_Date))
        ) AS rn
    FROM RemovalsWithCustID rc
    JOIN iSigma_Bill_Master bm ON bm.cust_id = rc.CustID
)

-- FINAL OUTPUT: % of removals within 2 weeks of their closest bill due date, by channel
SELECT
    RemovalChannel,
    COUNT(*) AS TotalRemovals,
    SUM(CASE WHEN DaysFromDueDate <= 14 THEN 1 ELSE 0 END) AS WithinTwoWeeksOfDueDate,
    ROUND(100.0 * SUM(CASE WHEN DaysFromDueDate <= 14 THEN 1 ELSE 0 END) / COUNT(*), 1) AS PctWithinTwoWeeks
FROM RankedBills
WHERE rn = 1
GROUP BY RemovalChannel
ORDER BY RemovalChannel;


-- ============================================================================
-- WHY: The first version measured distance to the NEAREST due date in either
-- direction, which is nearly always small just because bills recur monthly —
-- that's a math artifact, not a real signal. This version only looks FORWARD,
-- to the next bill still coming due after the removal, matching the original
-- "~66% of removals happen within two weeks of the next due date" methodology.
-- ============================================================================

WITH Removals AS (
    SELECT
        A.AccountID,
        A.Created AS RemovalDate,
        CASE WHEN A.CreatedBy = '0054T000001dhK1QAI' THEN 'Portal/Website' ELSE 'Agent' END AS RemovalChannel
    FROM dbo.vw_Salesforce_Autopay A
    WHERE A.Remove = 1
        AND A.Created >= DATEADD(MONTH, -6, CAST(GETDATE() AS DATE))
),

RemovalsWithCustID AS (
    SELECT
        r.AccountID,
        r.RemovalDate,
        r.RemovalChannel,
        b.CustID
    FROM Removals r
    JOIN dbo.vw_Salesforce_BillingAccount b ON b.ID = r.AccountID
),

NextBillOnly AS (
    -- Only bills due ON OR AFTER the removal date -- forward-looking only
    SELECT
        rc.AccountID,
        rc.RemovalDate,
        rc.RemovalChannel,
        bm.Due_Date,
        DATEDIFF(DAY, rc.RemovalDate, bm.Due_Date) AS DaysUntilDue,
        ROW_NUMBER() OVER (
            PARTITION BY rc.AccountID, rc.RemovalDate 
            ORDER BY bm.Due_Date ASC
        ) AS rn
    FROM RemovalsWithCustID rc
    JOIN iSigma_Bill_Master bm ON bm.cust_id = rc.CustID
    WHERE bm.Due_Date >= rc.RemovalDate
)

SELECT
    RemovalChannel,
    COUNT(*) AS TotalRemovals,
    SUM(CASE WHEN DaysUntilDue <= 14 THEN 1 ELSE 0 END) AS WithinTwoWeeksOfNextDueDate,
    ROUND(100.0 * SUM(CASE WHEN DaysUntilDue <= 14 THEN 1 ELSE 0 END) / COUNT(*), 1) AS PctWithinTwoWeeks
FROM NextBillOnly
WHERE rn = 1
GROUP BY RemovalChannel
ORDER BY RemovalChannel;



-- ============================================================================
-- WHY: Now that we know timing (near a bill due date) applies to both
-- channels, this checks WHY specifically for Agent-channel removals, since
-- those are the only ones with an actual call we can read. We're searching
-- what the customer/agent actually said for language matching each of the
-- three drivers Jonathan flagged: draft-date timing, fee shock, and
-- enrollment-without-consent.
--
-- HOW: For each Agent-channel removal, find the call that happened on the
-- same day (the call that presumably led to the removal), then search the
-- call summary text for keywords tied to each driver.
-- ============================================================================

WITH AgentRemovals AS (
    SELECT
        A.AccountID,
        A.Created AS RemovalDate,
        b.CustID
    FROM dbo.vw_Salesforce_Autopay A
    JOIN dbo.vw_Salesforce_BillingAccount b ON b.ID = A.AccountID
    WHERE A.Remove = 1
        AND A.CreatedBy <> '0054T000001dhK1QAI'  -- Agent channel only
        AND A.Created >= DATEADD(MONTH, -6, CAST(GETDATE() AS DATE))
),

RemovalCalls AS (
    -- Match each removal to a same-day call on that customer's account
    SELECT
        ar.AccountID,
        ar.RemovalDate,
        ivr.ContactID,
        ROW_NUMBER() OVER (
            PARTITION BY ar.AccountID, ar.RemovalDate 
            ORDER BY ABS(DATEDIFF(SECOND, ar.RemovalDate, ivr.CallDate))
        ) AS rn
    FROM AgentRemovals ar
    JOIN dbo.IVR ivr 
        ON ivr.AccountNumber = ar.CustID
        AND CAST(ivr.CallDate AS DATE) = CAST(ar.RemovalDate AS DATE)
        AND ivr.AgentTalkTime > 0
),

MatchedCallText AS (
    SELECT
        rc.AccountID,
        cai.[call.summary]
    FROM RemovalCalls rc
    JOIN Care_CallAI cai ON cai.ContactID = rc.ContactID
    WHERE rc.rn = 1
)

SELECT
    COUNT(*) AS TotalMatchedCalls,
    SUM(CASE WHEN [call.summary] LIKE '%draft date%' OR [call.summary] LIKE '%payment date%' OR [call.summary] LIKE '%due date%' OR [call.summary] LIKE '%mid-month%' OR [call.summary] LIKE '%1st%' THEN 1 ELSE 0 END) AS DraftDateTimingMentions,
    SUM(CASE WHEN [call.summary] LIKE '%activation fee%' OR [call.summary] LIKE '%surprise fee%' OR [call.summary] LIKE '%first bill%' OR [call.summary] LIKE '%partial bill%' THEN 1 ELSE 0 END) AS FeeShockMentions,
    SUM(CASE WHEN [call.summary] LIKE '%never agreed%' OR [call.summary] LIKE '%did not authorize%' OR [call.summary] LIKE '%without consent%' OR [call.summary] LIKE '%never signed up%' OR [call.summary] LIKE '%never enrolled%' THEN 1 ELSE 0 END) AS ConsentDisputeMentions
FROM MatchedCallText;



-- WHY: The keyword search likely missed real mentions of fee shock and
-- consent disputes because the guessed phrases don't match how people
-- actually talk. Let's read a sample of real call summaries to find the
-- actual language before refining the search.

WITH AgentRemovals AS (
    SELECT A.AccountID, A.Created AS RemovalDate, b.CustID
    FROM dbo.vw_Salesforce_Autopay A
    JOIN dbo.vw_Salesforce_BillingAccount b ON b.ID = A.AccountID
    WHERE A.Remove = 1
        AND A.CreatedBy <> '0054T000001dhK1QAI'
        AND A.Created >= DATEADD(MONTH, -6, CAST(GETDATE() AS DATE))
),
RemovalCalls AS (
    SELECT ar.AccountID, ar.RemovalDate, ivr.ContactID,
        ROW_NUMBER() OVER (PARTITION BY ar.AccountID, ar.RemovalDate ORDER BY ABS(DATEDIFF(SECOND, ar.RemovalDate, ivr.CallDate))) AS rn
    FROM AgentRemovals ar
    JOIN dbo.IVR ivr ON ivr.AccountNumber = ar.CustID
        AND CAST(ivr.CallDate AS DATE) = CAST(ar.RemovalDate AS DATE)
        AND ivr.AgentTalkTime > 0
)

SELECT TOP 30 cai.[call.summary]
FROM RemovalCalls rc
JOIN Care_CallAI cai ON cai.ContactID = rc.ContactID
WHERE rc.rn = 1
ORDER BY NEWID();  -- random sample

-- ============================================================================
-- WHY: The random sample of real call summaries showed customers/agents use
-- different language than we guessed, AND revealed a major driver category
-- (card expired/lost/changed) that wasn't on the original list at all. This
-- rebuilds the search using the ACTUAL phrases seen in real calls.
-- ============================================================================

WITH AgentRemovals AS (
    SELECT A.AccountID, A.Created AS RemovalDate, b.CustID
    FROM dbo.vw_Salesforce_Autopay A
    JOIN dbo.vw_Salesforce_BillingAccount b ON b.ID = A.AccountID
    WHERE A.Remove = 1
        AND A.CreatedBy <> '0054T000001dhK1QAI'
        AND A.Created >= DATEADD(MONTH, -6, CAST(GETDATE() AS DATE))
),
RemovalCalls AS (
    SELECT ar.AccountID, ar.RemovalDate, ivr.ContactID,
        ROW_NUMBER() OVER (PARTITION BY ar.AccountID, ar.RemovalDate ORDER BY ABS(DATEDIFF(SECOND, ar.RemovalDate, ivr.CallDate))) AS rn
    FROM AgentRemovals ar
    JOIN dbo.IVR ivr ON ivr.AccountNumber = ar.CustID
        AND CAST(ivr.CallDate AS DATE) = CAST(ar.RemovalDate AS DATE)
        AND ivr.AgentTalkTime > 0
),
MatchedCallText AS (
    SELECT rc.AccountID, cai.[call.summary] AS Summary
    FROM RemovalCalls rc
    JOIN Care_CallAI cai ON cai.ContactID = rc.ContactID
    WHERE rc.rn = 1
)

SELECT
    COUNT(*) AS TotalMatchedCalls,
    SUM(CASE WHEN Summary LIKE '%before the due date%' OR Summary LIKE '%earlier than expected%' 
        OR Summary LIKE '%early autopay%' OR Summary LIKE '%withdrawn earlier%' OR Summary LIKE '%before that date%' 
        THEN 1 ELSE 0 END) AS DraftTimingMismatch,
    SUM(CASE WHEN Summary LIKE '%expired card%' OR Summary LIKE '%lost%card%' OR Summary LIKE '%cancel%card%' 
        OR Summary LIKE '%new card%' OR Summary LIKE '%update%card%' OR Summary LIKE '%update%payment method%'
        THEN 1 ELSE 0 END) AS CardChangeIssue,
    SUM(CASE WHEN Summary LIKE '%overdraft%' OR Summary LIKE '%insufficient funds%' OR Summary LIKE '%lack of funds%'
        THEN 1 ELSE 0 END) AS OverdraftAvoidance,
    SUM(CASE WHEN Summary LIKE '%double payment%' OR Summary LIKE '%duplicate payment%' OR Summary LIKE '%duplicate $%'
        THEN 1 ELSE 0 END) AS DuplicatePaymentError,
    SUM(CASE WHEN Summary LIKE '%activation fee%' OR Summary LIKE '%surprise fee%' OR Summary LIKE '%unexpected charge%'
        THEN 1 ELSE 0 END) AS FeeShock,
    SUM(CASE WHEN Summary LIKE '%never agreed%' OR Summary LIKE '%did not authorize%' OR Summary LIKE '%without consent%'
        OR Summary LIKE '%never enrolled%' OR Summary LIKE '%don''t remember%enroll%'
        THEN 1 ELSE 0 END) AS ConsentDispute
FROM MatchedCallText;



-- WHY: The draft-timing count (25) looks far too low compared to the sample
-- evidence. Let's pull the actual matching rows to confirm the logic works
-- correctly before trusting any of these smaller numbers.

WITH AgentRemovals AS (
    SELECT A.AccountID, A.Created AS RemovalDate, b.CustID
    FROM dbo.vw_Salesforce_Autopay A
    JOIN dbo.vw_Salesforce_BillingAccount b ON b.ID = A.AccountID
    WHERE A.Remove = 1
        AND A.CreatedBy <> '0054T000001dhK1QAI'
        AND A.Created >= DATEADD(MONTH, -6, CAST(GETDATE() AS DATE))
),
RemovalCalls AS (
    SELECT ar.AccountID, ar.RemovalDate, ivr.ContactID,
        ROW_NUMBER() OVER (PARTITION BY ar.AccountID, ar.RemovalDate ORDER BY ABS(DATEDIFF(SECOND, ar.RemovalDate, ivr.CallDate))) AS rn
    FROM AgentRemovals ar
    JOIN dbo.IVR ivr ON ivr.AccountNumber = ar.CustID
        AND CAST(ivr.CallDate AS DATE) = CAST(ar.RemovalDate AS DATE)
        AND ivr.AgentTalkTime > 0
)

SELECT TOP 15 cai.[call.summary]
FROM RemovalCalls rc
JOIN Care_CallAI cai ON cai.ContactID = rc.ContactID
WHERE rc.rn = 1
    AND (cai.[call.summary] LIKE '%before the due date%' 
        OR cai.[call.summary] LIKE '%earlier than expected%'
        OR cai.[call.summary] LIKE '%early autopay%' 
        OR cai.[call.summary] LIKE '%withdrawn earlier%' 
        OR cai.[call.summary] LIKE '%before that date%');




-- ============================================================================
-- WHY: Card/payment-method changes are the biggest driver we found (38.1%),
-- but that number alone doesn't tell us if it's a real problem. If most of
-- these customers quietly turn autopay back on once they update their new
-- card, this is just temporary friction, not real churn. If they don't come
-- back, it's a genuine retention issue worth fixing.
--
-- HOW: For each card-change-driven removal, check whether that same account
-- has any "Add" (re-enrollment) action within 60 days afterward.
-- ============================================================================

WITH AgentRemovals AS (
    SELECT A.AccountID, A.Created AS RemovalDate, b.CustID
    FROM dbo.vw_Salesforce_Autopay A
    JOIN dbo.vw_Salesforce_BillingAccount b ON b.ID = A.AccountID
    WHERE A.Remove = 1
        AND A.CreatedBy <> '0054T000001dhK1QAI'
        AND A.Created >= DATEADD(MONTH, -6, CAST(GETDATE() AS DATE))
),
RemovalCalls AS (
    SELECT ar.AccountID, ar.RemovalDate, ivr.ContactID,
        ROW_NUMBER() OVER (PARTITION BY ar.AccountID, ar.RemovalDate ORDER BY ABS(DATEDIFF(SECOND, ar.RemovalDate, ivr.CallDate))) AS rn
    FROM AgentRemovals ar
    JOIN dbo.IVR ivr ON ivr.AccountNumber = ar.CustID
        AND CAST(ivr.CallDate AS DATE) = CAST(ar.RemovalDate AS DATE)
        AND ivr.AgentTalkTime > 0
),
CardChangeRemovals AS (
    SELECT rc.AccountID, rc.RemovalDate
    FROM RemovalCalls rc
    JOIN Care_CallAI cai ON cai.ContactID = rc.ContactID
    WHERE rc.rn = 1
        AND (cai.[call.summary] LIKE '%expired card%' OR cai.[call.summary] LIKE '%lost%card%' 
            OR cai.[call.summary] LIKE '%cancel%card%' OR cai.[call.summary] LIKE '%new card%' 
            OR cai.[call.summary] LIKE '%update%card%' OR cai.[call.summary] LIKE '%update%payment method%')
),
ReEnrollCheck AS (
    SELECT
        ccr.AccountID,
        ccr.RemovalDate,
        CASE WHEN EXISTS (
            SELECT 1 FROM dbo.vw_Salesforce_Autopay a2
            WHERE a2.AccountID = ccr.AccountID
                AND a2.Add = 1
                AND a2.Created > ccr.RemovalDate
                AND a2.Created <= DATEADD(DAY, 60, ccr.RemovalDate)
        ) THEN 1 ELSE 0 END AS ReEnrolledWithin60Days
    FROM CardChangeRemovals ccr
)

SELECT
    COUNT(*) AS TotalCardChangeRemovals,
    SUM(ReEnrolledWithin60Days) AS ReEnrolledCount,
    ROUND(100.0 * SUM(ReEnrolledWithin60Days) / COUNT(*), 1) AS PctReEnrolledWithin60Days
FROM ReEnrollCheck;

