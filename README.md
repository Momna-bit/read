	
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
