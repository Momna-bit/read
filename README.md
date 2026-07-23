	
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






task 4 follow up

-- Confirm verification-status column name on dbo.IVR
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'IVR'
  AND (COLUMN_NAME LIKE '%Verif%' OR COLUMN_NAME LIKE '%Queue%');

-- Confirm actual values in VerificationStatus
SELECT DISTINCT VerificationStatus, COUNT(*) AS Cnt
FROM dbo.IVR
WHERE Department = 'Care'
  AND CallDate >= '2022-07-01'
GROUP BY VerificationStatus
ORDER BY Cnt DESC;

SELECT DISTINCT VerificationStatus, COUNT(*) AS Cnt
FROM dbo.IVR
WHERE Department = 'Care'
  AND CallDate >= '2022-07-01'
GROUP BY VerificationStatus
ORDER BY Cnt DESC;

-- STEP 4 (corrected): IVR containment rate using Jonathan's real definition
SELECT
    CAST(CallDate AS DATE) AS CallDay,
    COUNT(*) AS Calls,
    SUM(CASE WHEN VerificationStatus = 'Verified' AND (Queue IS NULL OR QueueTime = 0) THEN 1 ELSE 0 END) AS ContainedCalls,
    SUM(CASE WHEN QueueTime > 0 THEN 1 ELSE 0 END) AS UncontainedCalls,
    SUM(CASE WHEN VerificationStatus = 'Verified' OR QueueTime > 0 THEN 1 ELSE 0 END) AS ContainmentDenominator,
    1.0 - (
        CAST(SUM(CASE WHEN QueueTime > 0 THEN 1 ELSE 0 END) AS FLOAT)
        / NULLIF(SUM(CASE WHEN VerificationStatus = 'Verified' OR QueueTime > 0 THEN 1 ELSE 0 END), 0)
    ) AS IVRContainmentRate_Corrected
FROM dbo.IVR
WHERE Department = 'Care'
  AND CallType IN ('Inbound','Transfer')
  AND CallDate >= '2022-07-01'
GROUP BY CAST(CallDate AS DATE)
ORDER BY CallDay;


-- STEP 3 (corrected): Past-due customer count, active customers only
SELECT
    CAST(pd.[Date] AS DATE) AS CallDay,
    COUNT(DISTINCT pd.CustID) AS PastDueCustomerCount_ActiveOnly
FROM JESouth_CollectionAR_DailyDue pd
JOIN iSigma_Customer_Master cm
    ON cm.cust_id = pd.CustID
    AND cm.Market = 'Texas'
    AND cm.CustomerType = 'Residential'
    AND cm.FlowStart <= pd.[Date]
    AND (cm.FlowEnd IS NULL OR cm.FlowEnd >= pd.[Date])
WHERE pd.[Date] >= '2022-07-01'
    AND pd.AR > 0
GROUP BY CAST(pd.[Date] AS DATE)
ORDER BY CallDay;
