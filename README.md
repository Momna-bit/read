	
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
Bill PDF Audit Tool - Step 1: Inspect Raw Extraction
Before we can check bills against the PUCT checklist, we need to see
exactly what pdfplumber can pull out of a real bill PDF - the raw
text, and any tables it can detect.

Run from PowerShell:
    py inspect_bill.py "C:\\path\\to\\your\\sample_bill.pdf"
"""

import sys
import pdfplumber

if len(sys.argv) < 2:
    print("Usage: py inspect_bill.py \"path\\to\\bill.pdf\"")
    sys.exit(1)

PDF_PATH = sys.argv[1]

print(f"Opening: {PDF_PATH}\n")

with pdfplumber.open(PDF_PATH) as pdf:
    print(f"Number of pages: {len(pdf.pages)}\n")

    for page_num, page in enumerate(pdf.pages, start=1):
        print("=" * 70)
        print(f"PAGE {page_num}")
        print("=" * 70)

        # ---- STEP 1: Raw text, in reading order ----
        print("\n--- RAW TEXT ---\n")
        text = page.extract_text()
        if text:
            print(text)
        else:
            print("(No text found on this page - may be a scanned image)")

        # ---- STEP 2: Any tables pdfplumber can detect ----
        print("\n--- TABLES DETECTED ---\n")
        tables = page.extract_tables()
        if tables:
            for t_num, table in enumerate(tables, start=1):
                print(f"Table {t_num}:")
                for row in table:
                    print(row)
                print()
        else:
            print("(No tables detected on this page)")

        print("\n")

print("Done. Review the output above to see what we're working with.")




"""
Bill PDF Audit Tool - Step 2: Check Rules
Takes a bill PDF and checks it against the rules we've confirmed with
Abby so far:
  1. Residential solar energy message - must appear on every bill
  2. Critical Care message - must appear ONLY in April and October
  3. TDU emergency contact number - must match the correct number for
     that bill's service territory

Run from PowerShell:
    py check_bill_rules.py "Tara_Energy_Sample.pdf"
"""

import sys
import re
import pdfplumber

if len(sys.argv) < 2:
    print("Usage: py check_bill_rules.py \"path\\to\\bill.pdf\"")
    sys.exit(1)

PDF_PATH = sys.argv[1]

# ---- Known TDU emergency numbers by territory ----
# Add more here as Abby sends additional sample invoices.
TDU_EMERGENCY_NUMBERS = {
    "Centerpoint": "1-800-332-7143",
    "Oncor": "1-888-313-4747",
}

# Text we search for to figure out which TDU/territory this bill belongs to
TDU_TERRITORY_MARKERS = {
    "Centerpoint": ["centerpoint"],
    "Oncor": ["oncor"],
}


def load_bill_text(pdf_path):
    """Pull all text from every page into one big string for searching."""
    full_text = ""
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            text = page.extract_text()
            if text:
                full_text += text + "\n"
    return full_text


def normalize(text):
    """Lowercase and collapse whitespace, so matching isn't picky about spacing/case."""
    return re.sub(r"\s+", " ", text).lower()


def find_bill_month(text):
    """
    Look for a Bill Date like 07/11/26 and return the month number (1-12).
    Returns None if no bill date pattern is found.
    """
    match = re.search(r"bill date\s*:?\s*(\d{1,2})/(\d{1,2})/(\d{2,4})", text, re.IGNORECASE)
    if match:
        return int(match.group(1))
    return None


def detect_territory(norm_text):
    """Figure out which TDU/service territory this bill belongs to, based on
    which utility name appears in the emergency-contact section."""
    for territory, markers in TDU_TERRITORY_MARKERS.items():
        for marker in markers:
            if marker in norm_text:
                return territory
    return None


def check_solar_message(norm_text):
    found = "learn more about residential solar energy" in norm_text
    return {
        "rule": "1. Residential Solar Energy Message",
        "result": "PASS" if found else "FAIL",
        "detail": "Message found." if found else "Message NOT found - should appear on every residential bill.",
    }


def check_critical_care_message(norm_text, bill_month):
    # NOTE: exact wording of the real Critical Care message not yet confirmed -
    # using a placeholder search term. Update this once we have the exact text
    # from Abby's checklist reference.
    found = "critical care" in norm_text

    if bill_month in (4, 10):
        # Should be present in April (4) or October (10)
        ok = found
        detail = "Message found, correct for this month." if ok else "Message MISSING - required in April/October."
    else:
        # Should NOT be present in any other month
        ok = not found
        detail = "Correctly absent outside April/October." if ok else "Message found but bill is NOT April/October - should not appear."

    return {
        "rule": "2. Critical Care Required Message",
        "result": "PASS" if ok else "FAIL",
        "detail": detail,
    }


def check_tdu_number(norm_text, territory):
    if territory is None:
        return {
            "rule": "3. TDU Emergency Contact Number",
            "result": "SKIPPED",
            "detail": "Could not determine service territory from this bill - add a marker for it in TDU_TERRITORY_MARKERS.",
        }

    expected_number = TDU_EMERGENCY_NUMBERS.get(territory)
    if expected_number is None:
        return {
            "rule": "3. TDU Emergency Contact Number",
            "result": "SKIPPED",
            "detail": f"Territory '{territory}' detected, but we don't have a known number for it yet.",
        }

    found = expected_number in norm_text
    return {
        "rule": "3. TDU Emergency Contact Number",
        "result": "PASS" if found else "FAIL",
        "detail": (
            f"Territory: {territory}. Expected number {expected_number} found."
            if found
            else f"Territory: {territory}. Expected number {expected_number} NOT found on this bill."
        ),
    }


# ================= MAIN =================

print(f"Checking: {PDF_PATH}\n")

raw_text = load_bill_text(PDF_PATH)
norm_text = normalize(raw_text)

bill_month = find_bill_month(raw_text)
territory = detect_territory(norm_text)

print(f"Detected bill month: {bill_month if bill_month else 'NOT FOUND'}")
print(f"Detected service territory: {territory if territory else 'NOT FOUND'}")
print()

results = [
    check_solar_message(norm_text),
    check_critical_care_message(norm_text, bill_month),
    check_tdu_number(norm_text, territory),
]

print("=" * 60)
print("RESULTS")
print("=" * 60)
for r in results:
    print(f"\n{r['rule']}")
    print(f"  Result: {r['result']}")
    print(f"  Detail: {r['detail']}")

print("\nDone.")

