-- Run this by itself to see the real distinct Status values and how many
-- customers fall into each, so we can confirm Status <> 'I' actually
-- landed on genuinely active accounts (and not something like suspended,
-- pending, or another in-between status).

SELECT
      Status
    , COUNT(*) AS customer_count
FROM Analytics_ConstellationWH.dbo.iSigma_Customer_Master
WHERE CustomerType = 'Residential'
    AND Market = 'Texas'
GROUP BY Status
ORDER BY customer_count DESC;
