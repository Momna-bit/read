	
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
