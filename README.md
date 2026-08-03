	
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

