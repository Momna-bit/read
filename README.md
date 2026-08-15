	
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



"""
Bill PDF Audit Tool - Phase 1 Rule Checker
============================================
Checks a residential/commercial electric bill PDF against the Phase 1
presence-only compliance rules confirmed with Abby (Billing).

Rules checked:
  1. Solar message       - residential bills only, universal (not tied to solar enrollment)
  2. Refer a Friend       - residential bills only
  3. Power to Choose       - residential bills only
  4. Critical Care message - required on April/October bills, must NOT appear other months
  5. TDU emergency contact - must match the correct number for the bill's utility territory

Run:
    py check_bill_rules.py <path_to_pdf> --account-type residential --territory Oncor
    py check_bill_rules.py --batch <folder> --manifest manifest.csv

See README section at the bottom of this file for the manifest format.
"""

import argparse
import csv
import glob
import os
import re
import sys

import pdfplumber

# ---------------------------------------------------------------------------
# Known-good reference data (confirmed against 33 real sample bills,
# Amigo / Tara / Just Energy, all five territories, Aug 2026)
# ---------------------------------------------------------------------------

TDU_CONTACT_DIGITS = {
    "centerpoint": "8003327143",
    "oncor": "8883134747",
    "aep": "8662238508",     # covers AEP Central and AEP North - same number on all samples seen
    "tnmp": "8888667456",
    # Lubbock Power & Light is a municipal utility, not a standard deregulated
    # TDU - number varies and is not toll-free. Flagged, not auto-checked yet.
    # Confirm with Abby/Bidya whether Lubbock is even in Phase 1 scope.
}

SOLAR_PHRASE = "residential solar energy"
REFER_PHRASE = "refer a friend"
PTC_PHRASE = "powertochoose.com"
CRITICAL_CARE_PHRASE = "critical care or chronic condition"

CRITICAL_CARE_REQUIRED_MONTHS = {4, 10}  # April, October


# ---------------------------------------------------------------------------
# Core helpers
# ---------------------------------------------------------------------------

def extract_text(pdf_path):
    """Pull all text from every page of the PDF."""
    text = ""
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            text += (page.extract_text() or "") + "\n"
    return text


def digits_only(s):
    return re.sub(r"\D", "", s)


def find_bill_date(text):
    """
    Looks for 'Bill Date : MM/DD/YY' or 'Bill Date: MM/DD/YY' near the top
    of the bill. Returns (month, year) as ints, or (None, None) if not found.
    """
    match = re.search(r"Bill Date\s*:?\s*(\d{2})/(\d{2})/(\d{2})", text)
    if not match:
        return None, None
    month = int(match.group(1))
    year = 2000 + int(match.group(3))
    return month, year


def normalize_territory(territory):
    t = territory.strip().lower()
    if "center" in t:
        return "centerpoint"
    if "oncor" in t:
        return "oncor"
    if "aep" in t:
        return "aep"
    if "tnmp" in t:
        return "tnmp"
    if "lubbock" in t:
        return "lubbock"
    return t


# ---------------------------------------------------------------------------
# Rule checks - each returns (status, detail) where status is
# "PASS", "FAIL", or "SKIP" (rule not applicable / not yet checkable)
# ---------------------------------------------------------------------------

def check_solar(text, account_type):
    present = SOLAR_PHRASE in text.lower()
    if account_type == "residential":
        return ("PASS", "Solar message present, as required") if present else \
               ("FAIL", "Solar message MISSING - required on all residential bills")
    else:
        return ("FAIL", "Solar message present but should NOT appear on commercial bills") if present else \
               ("PASS", "Solar message correctly absent on commercial bill")


def check_refer_a_friend(text, account_type):
    present = REFER_PHRASE in text.lower()
    if account_type == "residential":
        return ("PASS", "Refer a Friend message present") if present else \
               ("FAIL", "Refer a Friend message MISSING on residential bill")
    else:
        return ("FAIL", "Refer a Friend message present but should NOT appear on commercial bills") if present else \
               ("PASS", "Refer a Friend correctly absent on commercial bill")


def check_power_to_choose(text, account_type):
    present = PTC_PHRASE in text.lower()
    if account_type == "residential":
        return ("PASS", "Power to Choose message present") if present else \
               ("FAIL", "Power to Choose message MISSING on residential bill")
    else:
        return ("FAIL", "Power to Choose message present but should NOT appear on commercial bills") if present else \
               ("PASS", "Power to Choose correctly absent on commercial bill")


def check_critical_care(text, bill_month):
    present = CRITICAL_CARE_PHRASE in text.lower()
    if bill_month is None:
        return ("SKIP", "Could not determine bill month - Critical Care check skipped")
    required = bill_month in CRITICAL_CARE_REQUIRED_MONTHS
    if required and present:
        return ("PASS", f"Critical Care message present in required month ({bill_month})")
    if required and not present:
        return ("FAIL", f"Critical Care message MISSING in required month ({bill_month})")
    if not required and present:
        return ("FAIL", f"Critical Care message present in month {bill_month} - should ONLY appear in April/October")
    return ("PASS", f"Critical Care correctly absent outside April/October (month {bill_month})")


def check_tdu_contact(text, territory):
    norm = normalize_territory(territory)
    if norm == "lubbock":
        return ("SKIP", "Lubbock is a municipal utility - not yet in confirmed TDU scope")
    expected = TDU_CONTACT_DIGITS.get(norm)
    if not expected:
        return ("SKIP", f"Unknown territory '{territory}' - no reference number on file")
    text_digits = digits_only(text)
    if expected in text_digits:
        return ("PASS", f"Correct {territory} emergency number found")
    return ("FAIL", f"Expected {territory} emergency number not found on bill")


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def check_bill(pdf_path, account_type, territory):
    """
    account_type: 'residential' or 'commercial'
    territory: one of Centerpoint / Oncor / AEP / TNMP / Lubbock
    """
    account_type = account_type.strip().lower()
    text = extract_text(pdf_path)
    bill_month, bill_year = find_bill_date(text)

    results = {
        "file": os.path.basename(pdf_path),
        "account_type": account_type,
        "territory": territory,
        "bill_month": bill_month,
        "bill_year": bill_year,
    }

    results["solar"] = check_solar(text, account_type)
    results["refer_a_friend"] = check_refer_a_friend(text, account_type)
    results["power_to_choose"] = check_power_to_choose(text, account_type)
    results["critical_care"] = check_critical_care(text, bill_month)
    results["tdu_contact"] = check_tdu_contact(text, territory)

    return results


def print_result(results):
    print(f"\n{results['file']}")
    print(f"  Account type: {results['account_type']} | Territory: {results['territory']} | Bill month: {results['bill_month']}")
    for rule in ["solar", "refer_a_friend", "power_to_choose", "critical_care", "tdu_contact"]:
        status, detail = results[rule]
        marker = {"PASS": "[PASS]", "FAIL": "[FAIL]", "SKIP": "[SKIP]"}[status]
        print(f"  {marker} {rule:18} {detail}")


def guess_account_type_and_territory_from_filename(filename):
    """Best-effort fallback for batch mode when no manifest is supplied.
    NOTE: filenames are not always reliable (see mislabeled Tara TNMP
    sample found during validation) - manifest input is preferred."""
    lower = filename.lower()
    account_type = "residential" if "residential" in lower else "commercial"
    territory = "Unknown"
    for t in ["Centerpoint", "Oncor", "AEP", "TNMP", "Lubbock"]:
        if t.lower() in lower:
            territory = t
            break
    return account_type, territory


def run_batch(folder, manifest_path=None):
    manifest = {}
    if manifest_path:
        with open(manifest_path, newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                manifest[row["filename"]] = (row["account_type"], row["territory"])

    pdf_files = sorted(glob.glob(os.path.join(folder, "**", "*.pdf"), recursive=True))
    if not pdf_files:
        print(f"No PDFs found in {folder}")
        return

    all_results = []
    for path in pdf_files:
        fname = os.path.basename(path)
        if fname in manifest:
            account_type, territory = manifest[fname]
        else:
            account_type, territory = guess_account_type_and_territory_from_filename(fname)
        results = check_bill(path, account_type, territory)
        print_result(results)
        all_results.append(results)

    # Summary
    total = len(all_results)
    fails = [r for r in all_results for rule in ["solar", "refer_a_friend", "power_to_choose", "critical_care", "tdu_contact"] if r[rule][0] == "FAIL"]
    print(f"\n{'='*60}")
    print(f"SUMMARY: {total} bills checked, {len(fails)} rule failures found")
    print(f"{'='*60}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Bill PDF Audit Tool - Phase 1 rule checker")
    parser.add_argument("pdf", nargs="?", help="Path to a single PDF to check")
    parser.add_argument("--account-type", choices=["residential", "commercial"], help="Account type for single-file mode")
    parser.add_argument("--territory", help="Utility territory for single-file mode (Centerpoint/Oncor/AEP/TNMP/Lubbock)")
    parser.add_argument("--batch", help="Folder to batch-check (recursively finds all PDFs)")
    parser.add_argument("--manifest", help="Optional CSV with columns: filename,account_type,territory")
    args = parser.parse_args()

    if args.batch:
        run_batch(args.batch, args.manifest)
    elif args.pdf:
        if not args.account_type or not args.territory:
            print("Single-file mode requires --account-type and --territory")
            sys.exit(1)
        results = check_bill(args.pdf, args.account_type, args.territory)
        print_result(results)
    else:
        parser.print_help()

# ---------------------------------------------------------------------------
# Manifest CSV format (for --batch --manifest):
#   filename,account_type,territory
#   Amigo Residential Account_Oncor Utility_...pdf,residential,Oncor
#   Tara Commercial Account_AEP Central Utility_...pdf,commercial,AEP
#
# Manifest is preferred over filename-guessing because filenames can be
# wrong (confirmed during validation - one Tara file labeled "Residential"
# was actually a commercial account).
# ---------------------------------------------------------------------------


py check_bill_rules.py --batch "C:\Users\MAli\OneDrive - Just Energy Corp\Desktop\Bill pdf"

py check_bill_rules.py --batch "C:\Users\MAli\OneDrive - Just Energy Corp\Desktop\Tara Commercial_Residential Invoices_All Utilities_Solar_Critical Care Message"
py check_bill_rules.py --batch "C:\Users\MAli\OneDrive - Just Energy Corp\Desktop\JE Commercial_Residential Invoices_All Utilities_Solar and Critical Message"
py check_bill_rules.py --batch "C:\Users\MAli\OneDrive - Just Energy Corp\Desktop\Amigoo Commercial_Residential Invoices_All Utilities_Solar_Critical Care Message"
py check_bill_rules.py --batch "C:\Users\MAli\OneDrive - Just Energy Corp\Desktop\Tara Commercial_Residential Invoices_All Utilities_Solar_Critical Care Message"
py check_bill_rules.py "C:\Users\MAli\OneDrive - Just Energy Corp\Desktop\Tara Commercial_Residential Invoices_All Utilities_Solar_Critical Care Message\Tara Residential Account_TNMP Utility_Critical Care Message 2206100154_92604156076_20260424.pdf" --account-type commercial --territory TNMP



-- STEP 1: Find the relevant columns in iSigma_Customer_Master
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Customer_Master'
  AND (
        COLUMN_NAME LIKE '%CustomerType%'
     OR COLUMN_NAME LIKE '%AccountNumber%'
     OR COLUMN_NAME LIKE '%Acct%'
     OR COLUMN_NAME LIKE '%TDU%'
     OR COLUMN_NAME LIKE '%TDSP%'
     OR COLUMN_NAME LIKE '%Utility%'
     OR COLUMN_NAME LIKE '%Market%'
      )
ORDER BY COLUMN_NAME;



-- STEP 2: Find the account/customer identifier column, and preview
-- what values CustomerType and Utility actually hold
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Customer_Master'
  AND (
        COLUMN_NAME LIKE '%cust_id%'
     OR COLUMN_NAME LIKE '%Account%'
     OR COLUMN_NAME LIKE '%Acct%'
     OR COLUMN_NAME LIKE '%ID%'
      )
ORDER BY COLUMN_NAME;

-- STEP 3: Preview the actual values these fields hold
SELECT DISTINCT CustomerType FROM iSigma_Customer_Master;

SELECT DISTINCT Utility FROM iSigma_Customer_Master;

-- STEP 4: Find the account number column in the Bill Master table
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Bill_Master'
  AND (
        COLUMN_NAME LIKE '%Acct%'
     OR COLUMN_NAME LIKE '%Account%'
     OR COLUMN_NAME LIKE '%cust_id%'
     OR COLUMN_NAME LIKE '%Bill%'
      )
ORDER BY COLUMN_NAME;


SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Bill_Master'
ORDER BY COLUMN_NAME;



-- STEP 5: Confirm Bill_No and cust_id map to the real Acct # / Bill # from the PDF
SELECT Bill_No, cust_id, Bill_Date
FROM iSigma_Bill_Master
WHERE Bill_No = '92604166649';


-- STEP 6: Full lookup - pull account type and utility for a given Bill #
SELECT
    bm.Bill_No,
    bm.cust_id,
    bm.Bill_Date,
    cm.CustomerType,
    cm.Utility
FROM iSigma_Bill_Master bm
JOIN iSigma_Customer_Master cm
    ON bm.cust_id = cm.cust_id
WHERE bm.Bill_No = '92604166649';



-- STEP 7: Batch version - generates manifest data for many bills at once
SELECT
    bm.Bill_No,
    cm.CustomerType AS account_type,
    CASE
        WHEN cm.Utility = 'Centerpoint Energy' THEN 'Centerpoint'
        WHEN cm.Utility = 'Oncor' THEN 'Oncor'
        WHEN cm.Utility LIKE 'AEP Texas%' THEN 'AEP'
        WHEN cm.Utility = 'Texas-New Mexico Power Co' THEN 'TNMP'
        WHEN cm.Utility = 'Lubbock Power & Light' THEN 'Lubbock'
        ELSE cm.Utility
    END AS territory
FROM iSigma_Bill_Master bm
JOIN iSigma_Customer_Master cm
    ON bm.cust_id = cm.cust_id
WHERE bm.Bill_No IN (
    '92604166649', '92604163592', '92604163600', '92604166674',
    '92604164716', '92604161779', '92604160535', '92604166034', '92604166256'
    -- add more Bill Numbers here as needed, comma-separated
);



SELECT
    bm.Bill_No,
    cm.CustomerType AS account_type,
    CASE
        WHEN cm.Utility = 'Centerpoint Energy' THEN 'Centerpoint'
        WHEN cm.Utility = 'Oncor' THEN 'Oncor'
        WHEN cm.Utility LIKE 'AEP Texas%' THEN 'AEP'
        WHEN cm.Utility = 'Texas-New Mexico Power Co' THEN 'TNMP'
        WHEN cm.Utility = 'Lubbock Power & Light' THEN 'Lubbock'
        ELSE cm.Utility
    END AS territory
FROM iSigma_Bill_Master bm
JOIN iSigma_Customer_Master cm
    ON bm.cust_id = cm.cust_id
WHERE bm.Bill_No IN (
    -- Amigo (9)
    '92604166649','92604163592','92604163600','92604166674',
    '92604164716','92604161779','92604160535','92604166034','92604166256',
    -- Tara (11)
    '92604155403','92604155183','92604156426','92604155471',
    '92604156277','92604157067','92604156399','92604137649',
    '92604157095','92604156076','92604156887',
    -- Just Energy (11)
    '2604438376','2604436519','2604359528','2604376791','2604352721',
    '2604439431','2604438995','2604362922','2604363680','2604368525','2604377890'
);



-- STEP 1: Repeat-caller day-of-week pattern (July 2026, same month/definition as the original 28.27% finding)
WITH ConnectedCalls AS (
    SELECT AccountNumber, CAST(CallDate AS DATE) AS CallDay,
        COUNT(DISTINCT InitialContact) AS Calls
    FROM Analytics_ConstellationWH.dbo.IVR
    WHERE Department = 'CARE' AND CallType IN ('INBOUND', 'Transfer')
        AND CAST(CallDate AS DATE) >= '2026-07-01' AND CAST(CallDate AS DATE) < '2026-08-01'
        AND AccountNumber IS NOT NULL
        AND VerificationStatus NOT IN ('Abandoned', 'Not Attempted')
    GROUP BY AccountNumber, CAST(CallDate AS DATE)
)
SELECT
    DATENAME(WEEKDAY, CallDay) AS DayOfWeek,
    DATEPART(WEEKDAY, CallDay) AS DayNum,
    COUNT(*) AS TotalCallDays,
    SUM(CASE WHEN Calls >= 2 THEN 1 ELSE 0 END) AS RepeatCallDays,
    ROUND(100.0 * SUM(CASE WHEN Calls >= 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS RepeatRatePct
FROM ConnectedCalls
GROUP BY DATENAME(WEEKDAY, CallDay), DATEPART(WEEKDAY, CallDay)
ORDER BY DayNum;


-- STEP 1: Find the column that holds call reason / complaint category tags
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Care_CallAI'
  AND (
        COLUMN_NAME LIKE '%Reason%'
     OR COLUMN_NAME LIKE '%Category%'
     OR COLUMN_NAME LIKE '%Complaint%'
     OR COLUMN_NAME LIKE '%Tag%'
     OR COLUMN_NAME LIKE '%Classif%'
     OR COLUMN_NAME LIKE '%Issue%'
      )
ORDER BY COLUMN_NAME;


-- STEP 2: Find all distinct reason values containing "glitch" or "system"
-- across the relevant classification columns
SELECT DISTINCT [call.reasongranular], COUNT(*) AS CallCount
FROM Analytics_Constellation.dbo.Care_CallAI
WHERE [call.reasongranular] LIKE '%glitch%' OR [call.reasongranular] LIKE '%system%'
GROUP BY [call.reasongranular]
ORDER BY CallCount DESC;



-- Also check the broader reason column and IVRIssues in case it's tagged there instead
SELECT DISTINCT [call.reason], COUNT(*) AS CallCount
FROM Analytics_Constellation.dbo.Care_CallAI
WHERE [call.reason] LIKE '%glitch%' OR [call.reason] LIKE '%system%'
GROUP BY [call.reason]
ORDER BY CallCount DESC;



-- STEP 3a: Find the actual date column name on Care_CallAI
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Care_CallAI'
  AND (
        COLUMN_NAME LIKE '%date%'
     OR COLUMN_NAME LIKE '%Date%'
      )
ORDER BY COLUMN_NAME;


-- STEP 3 (corrected): Check if "Payment system issue" calls cluster by date
SELECT
    [Date] AS CallDay,
    COUNT(*) AS CallCount
FROM Analytics_ConstellationWH.dbo.Care_CallAI
WHERE [call.reasongranular] = 'Payment system issue'
GROUP BY [Date]
ORDER BY CallDay;



-- STEP 4: Confirm the three spike days precisely, plus overall context
SELECT
    [Date] AS CallDay,
    COUNT(*) AS CallCount
FROM Analytics_ConstellationWH.dbo.Care_CallAI
WHERE [call.reasongranular] = 'Payment system issue'
  AND [Date] IN ('2026-04-27', '2026-07-07', '2026-08-12')
GROUP BY [Date]
ORDER BY CallDay;


-- STEP 5: Total "Payment system issue" calls across the whole period, for framing
SELECT
    COUNT(*) AS TotalPaymentSystemCalls,
    MIN([Date]) AS EarliestDate,
    MAX([Date]) AS LatestDate
FROM Analytics_ConstellationWH.dbo.Care_CallAI
WHERE [call.reasongranular] = 'Payment system issue';
