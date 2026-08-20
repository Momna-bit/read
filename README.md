	
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
Bill PDF Audit Tool - Phase 1 Rule Checker (Full: Sections 1-9)
=================================================================
Checks a residential/commercial electric bill PDF against the Phase 1
presence-only compliance checklist confirmed with Abby (Billing).

SECTIONS COVERED (text-search / presence checks):
  1. Messages & Regulatory Notices  - stable, validated against 33 real bills
  2. Customer Information           - validated against 1 real bill (Tara)
  3. Billing Summary                - validated against 1 real bill (Tara)
  4. Meter Information              - built from 1 real bill, UNVALIDATED beyond it
  5. Charges & Taxes                - built from 1 real bill, UNVALIDATED beyond it
  6. Agreement Details / Product    - built from 1 real bill, UNVALIDATED beyond it
  8. Usage History                  - built from 1 real bill, UNVALIDATED beyond it
  9. Payment Coupon / Remittance    - built from 1 real bill, UNVALIDATED beyond it

NOT COVERED - SECTION 10 (PDF Display & Formatting):
  Deliberately NOT implemented here. This section (no overlapping/truncated
  text, correct page breaks, fonts/alignment, no blank pages, English +
  Spanish validation) is fundamentally a VISUAL/LAYOUT problem, not a text
  search problem - the same text can extract identically whether it's
  overlapping garbage on the page or perfectly laid out. Faking a text-based
  check here would produce false confidence, which is worse than an honest
  gap. This needs a different approach entirely (e.g. rendering each page to
  an image and doing visual/positional analysis with pdfplumber's word
  coordinates, or a vision-based check) - flag as a separate build, not an
  extension of this script.

IMPORTANT CAVEAT ON SECTIONS 4-6, 8-9:
  Only ONE real bill format (Tara Energy, residential TNMP, commercial
  sample) has been checked by hand so far. Sections 2 and 3 both needed
  real fixes after checking real text - the checklist's assumed wording
  ("Amount Due") didn't match the real bill ("Due Amount"). The same is
  almost certainly true here for Amigo and Just Energy formats. Treat
  every FAIL from Sections 4-6, 8-9 as "needs a manual look", not as a
  confirmed compliance gap, until spot-checked against more real bills.

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
}

SOLAR_PHRASE = "residential solar energy"
REFER_PHRASE = "refer a friend"
PTC_PHRASE = "powertochoose.com"
CRITICAL_CARE_PHRASE = "critical care or chronic condition"

CRITICAL_CARE_REQUIRED_MONTHS = {4, 10}  # April, October

MONTH_ABBR = r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)"


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


def _label_then_nearby_value(text, label_pattern, value_pattern, window=150):
    """
    Shared helper: PDF table extraction often puts column headers on one
    line and values on a separate line below (not immediately adjacent),
    so checking label-followed-directly-by-value is too strict. Looks for
    the label, then checks if a matching value appears anywhere within
    `window` characters after it.
    """
    if not text:
        return False
    match = re.search(label_pattern, text)
    if not match:
        return False
    nearby = text[match.end(): match.end() + window]
    return bool(re.search(value_pattern, nearby))


# ---------------------------------------------------------------------------
# SECTION 1 checks - Messages & Regulatory Notices
# each returns (status, detail) where status is "PASS", "FAIL", or "SKIP"
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


def check_things_you_should_know(text):
    if "THINGS YOU SHOULD KNOW ABOUT YOUR BILL" in text.upper():
        return ("PASS", "Required 'THINGS YOU SHOULD KNOW ABOUT YOUR BILL' notice present")
    return ("FAIL", "MISSING required 'THINGS YOU SHOULD KNOW ABOUT YOUR BILL' notice")


def check_unauthorized_charges_notice(text, customer_care_phone):
    text_lower = text.lower()
    if "unauthorized charges" not in text_lower:
        return ("FAIL", "MISSING unauthorized charges notification")
    if customer_care_phone and customer_care_phone in text:
        return ("PASS", f"Unauthorized charges notice present with correct phone number ({customer_care_phone})")
    return ("PASS", "Unauthorized charges notice present (phone number not cross-checked)")


def check_puct_complaint_info(text):
    required_fragments = ["P.O. Box 13326", "78711", "936-7120"]
    missing = [f for f in required_fragments if f not in text]
    if not missing:
        return ("PASS", "PUCT complaint-filing info present and complete")
    return ("FAIL", f"PUCT complaint info incomplete - missing: {', '.join(missing)}")


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
# SECTION 2 checks - Customer Information
# ---------------------------------------------------------------------------

def check_account_number(text):
    """2.2 - Account Number present. Accepts 'Acct #', 'Account Number', etc."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)(account|acct)\.?\s*(number|no\.?|#)\s*[:\-]?\s*\d+"
    if re.search(pattern, text):
        return ("PASS", "Account number field found on bill.")
    return ("FAIL", "No labeled account number found (checked 'Account Number', 'Acct #', 'Acct No.').")


def check_service_address_and_esi_id(text):
    """2.3 / 2.5 combined - 'Service at Premise #' label + 17-digit ESI-ID-format value."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    esiid_format = r"\b10\d{15}\b"
    label_pattern = r"(?i)service\s*(address|at\s*premise)\s*#?\s*[:\-]?"
    has_label = re.search(label_pattern, text)
    has_esiid = re.search(esiid_format, text)
    if has_label and has_esiid:
        return ("PASS", "Service premise field found, with a value matching the expected 17-digit ESI ID format.")
    if has_esiid and not has_label:
        return ("PASS", "A 17-digit ESI-ID-format number was found, though not under a recognized label - verify manually.")
    if has_label and not has_esiid:
        return ("FAIL", "Service address/premise label found, but no ESI-ID-format value nearby - verify manually.")
    return ("FAIL", "No service address, premise number, or ESI ID found.")


def check_customer_name_and_billing_address(text):
    """
    2.1 / 2.4 - HONEST LIMITATION: no label exists for these on real bills.
    Returns REVIEW rather than a false PASS/FAIL.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    top_section = text[:600]
    address_block_pattern = r"[A-Z][a-zA-Z\s]+,\s*TX\s*\d{5}(-\d{4})?"
    if re.search(address_block_pattern, top_section):
        return ("REVIEW", "Address-shaped text found near the top of the bill (likely the customer name/address block) - no label exists to confirm automatically. Manual check needed.")
    return ("FAIL", "No name or address block detected near the top of the bill - worth a manual look, this may be a real gap or a layout this check doesn't cover yet.")


# ---------------------------------------------------------------------------
# SECTION 3 checks - Billing Summary
# ---------------------------------------------------------------------------

def check_bill_number(text):
    """3.1 - Bill Number present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)bill\s*(number|no\.?|#)\s*[:\-]?\s*\d+"
    if re.search(pattern, text):
        return ("PASS", "Bill number field found.")
    return ("FAIL", "No labeled bill number found.")


def check_bill_date_field(text):
    """3.2 - Bill Date present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)bill\s*date\s*[:\-]?\s*\d{1,2}/\d{1,2}/\d{2,4}"
    if re.search(pattern, text):
        return ("PASS", "Bill date field found.")
    return ("FAIL", "No labeled bill date found.")


def check_bill_period(text):
    """3.3 - Bill Period present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)bill\s*period\s*[:\-]?\s*\d{1,2}/\d{1,2}/\d{2,4}"
    if re.search(pattern, text):
        return ("PASS", "Bill period field found.")
    return ("FAIL", "No labeled bill period found.")


def check_previous_balance(text):
    """3.4 - Previous Balance present."""
    if _label_then_nearby_value(text, r"(?i)previous\s*balance", r"\$?-?\d"):
        return ("PASS", "Previous balance field found, with a nearby value.")
    return ("FAIL", "No labeled previous balance found (or no value nearby).")


def check_current_charges(text):
    """3.5 - Current Charges present. Accepts 'Current Charges' or 'New Charges'."""
    if _label_then_nearby_value(text, r"(?i)(current|new)\s*charges", r"\$?-?\d"):
        return ("PASS", "Current/new charges field found, with a nearby value.")
    return ("FAIL", "No labeled current/new charges found (checked both 'Current Charges' and 'New Charges').")


def check_payments_adjustments(text):
    """3.6 - Payments/Adjustments present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)payments\s*/?\s*adj(ustments?)?\.?\s*[:\-]?"
    if re.search(pattern, text):
        return ("PASS", "Payments/Adjustments field found.")
    return ("FAIL", "No labeled payments/adjustments field found.")


def check_amount_due(text):
    """3.7 - Amount Due present. Accepts 'Amount Due' or 'Due Amount'."""
    if _label_then_nearby_value(text, r"(?i)(amount\s*due|due\s*amount)", r"\$?\d"):
        return ("PASS", "Amount due field found, with a nearby value.")
    return ("FAIL", "No labeled amount due found (checked both 'Amount Due' and 'Due Amount').")


def check_due_date_field(text):
    """3.8 - Due Date present."""
    if _label_then_nearby_value(text, r"(?i)due\s*(date|by)", r"\d{1,2}/\d{1,2}/\d{2,4}"):
        return ("PASS", "Due date field found, with a nearby value.")
    return ("FAIL", "No labeled due date found (or no date value nearby).")


# ---------------------------------------------------------------------------
# SECTION 4 checks - Meter Information
# Built from real bill's meter table: "Meter | Type | Dates | Curr. Rd |
# Prev. Rd | Mult | Usage" header row, e.g. "348197676 ACT 03/23-04/22
# 23430 22904 1 526.00". UNVALIDATED against Amigo/Just Energy formats.
# ---------------------------------------------------------------------------

def check_meter_table_present(text):
    """
    4.1-4.6 combined - checks that the meter reading table itself is
    present (Meter/Type/Dates/Curr Rd/Prev Rd/Usage headers together).
    Combined into one check since these headers sit in one table row on
    the real bill checked - splitting into 6 separate checks would likely
    just fail identically for all 6 if the table format differs even
    slightly, giving false precision.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    required_headers = ["meter", "type", "curr", "prev", "usage"]
    lower = text.lower()
    missing = [h for h in required_headers if h not in lower]
    if not missing:
        return ("PASS", "Meter reading table headers found (Meter/Type/Curr Rd/Prev Rd/Usage).")
    return ("FAIL", f"Meter table appears incomplete or uses different labels - missing: {', '.join(missing)}. Verify manually.")


def check_actual_or_estimated_read(text):
    """
    4.2 - Actual vs. Estimated read indicator. Real bill uses 'ACT' as a
    table cell value, not a full word - checking for that short code plus
    the long-form alternates in case other brands spell it out.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)\b(ACT|EST|Actual|Estimated)\b"
    if re.search(pattern, text):
        return ("PASS", "Actual/Estimated read indicator found.")
    return ("FAIL", "No Actual/Estimated read indicator found (checked 'ACT', 'EST', 'Actual', 'Estimated').")


def check_usage_kwh_value(text):
    """4.6 - Usage (kWh) value present, near a 'Usage' label."""
    if _label_then_nearby_value(text, r"(?i)usage", r"[\d,]+\.\d{2}"):
        return ("PASS", "Usage value found near a 'Usage' label.")
    return ("FAIL", "No usage value found near a 'Usage' label - verify manually.")


# ---------------------------------------------------------------------------
# SECTION 5 checks - Charges & Taxes
# Built from real bill's charge line items: Base Charge, [Plan Name] Energy
# Plan, Market Securitization Debt Fin., ERCOT Admin Fee, TDSP Delivery
# Charges, City Tax, PUC Assessment, State Tax, Gross Receipt Reimb.
# NOTE: the average-price-per-kWh CALCULATION (compute cents/kWh excluding
# tax, compare to the printed value) is NOT implemented here - that is a
# numeric validation task, a different complexity tier from a presence
# check, and doing it wrong with unverified assumptions would be worse
# than leaving it as an explicit open item.
# ---------------------------------------------------------------------------

def check_energy_charges(text):
    """
    5.1 - Energy charges/rate/amount line item present. Brands label this
    differently: Tara/Amigo call it '[Plan Name] Energy Plan', Just
    Energy calls it 'Energy Charges' explicitly. Checking for either.
    """
    pattern = r"(?i)energy\s*(charges|plan)"
    if _label_then_nearby_value(text, pattern, r"\$?-?\d"):
        return ("PASS", "Energy charges/plan line item found, with a nearby value.")
    return ("FAIL", "No energy charges/plan line item found (checked 'Energy Charges' and '... Energy Plan').")


def check_base_charge(text):
    """
    5.2 - Base Charge line item present.
    NOTE: a real Amigo commercial bill checked has NO separate Base
    Charge line at all (likely folded into the plan/energy charge line
    instead) - a FAIL here may be a genuine brand/account-type
    difference, not a missing-field error. Verify manually before
    treating this as a compliance gap.
    """
    if _label_then_nearby_value(text, r"(?i)base\s*charge", r"\$?\d"):
        return ("PASS", "Base Charge line item found, with a nearby value.")
    return ("FAIL", "No 'Base Charge' line item found - may be genuinely absent on this brand/account type rather than missing, verify manually.")


def check_tdu_delivery_charges(text):
    """5.3 - TDU/TDSP delivery (pass-through) charges present."""
    pattern = r"(?i)(tdsp|tdu)\s*delivery"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "TDU/TDSP delivery charges found, with a nearby value.")
    return ("FAIL", "No TDU/TDSP delivery charges line item found.")


def check_gross_receipts_tax(text):
    """5.4 - Gross receipts tax/reimbursement present."""
    pattern = r"(?i)gross\s*receipt"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "Gross receipts tax/reimbursement line item found.")
    return ("FAIL", "No gross receipts tax/reimbursement line item found.")


def check_puc_assessment(text):
    """5.5 - PUC assessment present."""
    pattern = r"(?i)puc\s*assessment"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "PUC assessment line item found, with a nearby value.")
    return ("FAIL", "No PUC assessment line item found.")


def check_market_securitization(text):
    """5.6 - Market securitization charge present."""
    pattern = r"(?i)market\s*securitization"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "Market securitization line item found, with a nearby value.")
    return ("FAIL", "No market securitization line item found - note this may be brand-specific, not all REPs itemize this separately.")


def check_total_current_charges(text):
    """
    5.1/5.8 combined - the overall 'Total Current Charges' or
    'Total Amount Due' rollup line is present (energy charges + all
    line items summed).
    """
    pattern = r"(?i)total\s*(current\s*charges|amount\s*due)"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "Total charges/amount due rollup line found.")
    return ("FAIL", "No 'Total Current Charges' or 'Total Amount Due' rollup line found.")


# ---------------------------------------------------------------------------
# SECTION 6 checks - Agreement Details / Product Info
# Built from real bill: "Agreement Details" heading, date-range + plan name
# line, "The average price you paid for electricity this month is X¢ per
# kWh." message, "You have a valid contract until MM/DD/YYYY" message.
# variable_rate check is a best-guess phrase, NOT confirmed against a real
# variable-rate bill yet (the one bill checked has a fixed-rate plan).
# ---------------------------------------------------------------------------

def check_agreement_section(text):
    """6.1 - 'Agreement Details' section heading present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    if re.search(r"(?i)agreement\s*details", text):
        return ("PASS", "Agreement Details section heading found.")
    return ("FAIL", "No 'Agreement Details' section heading found.")


def check_contract_dates(text):
    """6.3 - Contract start/end or bill-cycle date range near Agreement Details."""
    if _label_then_nearby_value(text, r"(?i)agreement\s*details", r"\d{1,2}/\d{1,2}/\d{2,4}\s*-\s*\d{1,2}/\d{1,2}/\d{2,4}"):
        return ("PASS", "A date range was found near the Agreement Details section.")
    return ("FAIL", "No date range found near Agreement Details - verify manually.")


def check_expiration_notice(text):
    """
    6.4 - Contract expiration notice present.
    Accepts both word orders seen across brands: Tara/Amigo say "valid
    contract until MM/DD/YYYY", Just Energy says "contract valid until
    MM/DD/YYYY" - same information, swapped word order.
    """
    pattern = r"(?i)(valid\s*contract\s*until|contract\s*valid\s*until)\s*\d{1,2}/\d{1,2}/\d{2,4}"
    if re.search(pattern, text):
        return ("PASS", "Contract expiration notice found.")
    return ("FAIL", "No contract expiration notice found (checked both 'valid contract until' and 'contract valid until' wordings).")


def check_average_price_message(text):
    """6.5 - Average price per kWh message present (text only, not the calculation)."""
    pattern = r"(?i)average\s*price\s*you\s*paid\s*for\s*electricity"
    if re.search(pattern, text):
        return ("PASS", "Average price message found. NOTE: this only confirms the message text is present, not that the printed cents/kWh value is mathematically correct.")
    return ("FAIL", "No average price per kWh message found.")


def check_variable_rate_message(text):
    """
    6.6 - Variable rate disclosure message. UNCONFIRMED wording - the one
    real bill checked has a fixed-rate plan and doesn't show this message,
    so this pattern is a best guess, not verified against a real example.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)variable\s*rate"
    if re.search(pattern, text):
        return ("PASS", "A 'variable rate' phrase was found - verify this matches the actual required disclosure wording.")
    return ("SKIP", "No 'variable rate' phrase found - UNCONFIRMED whether this bill is even a variable-rate plan; this check hasn't been validated against a real variable-rate bill yet.")


# ---------------------------------------------------------------------------
# SECTION 8 checks - Usage History
# Built from real bill: "Usage history (KWH)" chart heading, with month
# abbreviations (Apr, May, Jun...) printed as axis labels below the chart.
# ---------------------------------------------------------------------------

def check_usage_history_heading(text):
    """8.1 - 'Usage history (KWH)' chart heading present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    if re.search(r"(?i)usage\s*history", text):
        return ("PASS", "Usage history chart heading found.")
    return ("FAIL", "No 'Usage history' chart heading found.")


def check_usage_history_month_labels(text):
    """
    8.2/8.3 - Historical monthly values / graph month labels. Checks for
    at least several 3-letter month abbreviations near the usage history
    heading, as a proxy for the chart's axis labels having extracted as
    text (charts/images may not always extract this way - a real gap
    here could also just mean the chart is an embedded image with no
    text layer, which this check can't distinguish from a missing chart).
    """
    match = re.search(r"(?i)usage\s*history", text)
    if not match:
        return ("FAIL", "No 'Usage history' section found to check for month labels.")
    nearby = text[match.end(): match.end() + 400]
    months_found = re.findall(MONTH_ABBR, nearby)
    if len(months_found) >= 6:
        return ("PASS", f"Found {len(months_found)} month labels near the usage history chart.")
    return ("FAIL", f"Only found {len(months_found)} month labels near usage history (expected ~12) - verify manually, chart may be an image with no text layer.")


# ---------------------------------------------------------------------------
# SECTION 9 checks - Payment Coupon / Remittance Stub
# Built from real bill: "Please return this portion with your payment"
# divider text, a long numeric string under the remittance barcode area,
# and a "Do Not Pay - AutoPay" flag seen on the autopay sample checked.
# Barcode/QR presence is explicitly NOT checked - see note below.
# ---------------------------------------------------------------------------

def check_remittance_stub_present(text):
    """9.1 - Return-payment / remittance stub section present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)please\s*return\s*this\s*portion\s*with\s*your\s*payment"
    if re.search(pattern, text):
        return ("PASS", "Remittance stub divider text found ('Please return this portion with your payment').")
    return ("FAIL", "No remittance stub divider text found - verify manually, wording may differ by brand.")


def check_stub_reference_number(text):
    """
    9.8 - Long reference/routing number on the stub (OCR line under the
    barcode). Real bill showed a 30+ digit string. This is a weak proxy -
    a false PASS is possible if an unrelated long digit string appears
    elsewhere on the page.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"\b\d{20,}\b"
    if re.search(pattern, text):
        return ("PASS", "A long reference/routing number (20+ digits) was found - likely the stub OCR line, but not position-verified.")
    return ("FAIL", "No long reference/routing number found on the stub.")


def check_barcode_or_qr_present(text):
    """
    9.7 - Barcode/QR code presence. NOT CHECKABLE via text extraction - a
    barcode/QR is an image, not text, so pdfplumber's text layer will
    never show it either way. This always returns SKIP rather than a
    false PASS or FAIL. Confirming this needs an image-based check
    (e.g. counting embedded images on the stub page), which is a
    different kind of check from everything else in this script.
    """
    return ("SKIP", "Barcode/QR presence cannot be checked via text extraction - needs an image-based check, not implemented here.")


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

    # Section 1
    results["solar"] = check_solar(text, account_type)
    results["refer_a_friend"] = check_refer_a_friend(text, account_type)
    results["power_to_choose"] = check_power_to_choose(text, account_type)
    results["critical_care"] = check_critical_care(text, bill_month)
    results["things_you_should_know"] = check_things_you_should_know(text)
    results["unauthorized_charges"] = check_unauthorized_charges_notice(text, None)
    results["puct_complaint_info"] = check_puct_complaint_info(text)
    results["tdu_contact"] = check_tdu_contact(text, territory)

    # Section 2
    results["account_number"] = check_account_number(text)
    results["service_address_esi_id"] = check_service_address_and_esi_id(text)
    results["customer_name_billing_address"] = check_customer_name_and_billing_address(text)

    # Section 3
    results["bill_number"] = check_bill_number(text)
    results["bill_date_field"] = check_bill_date_field(text)
    results["bill_period"] = check_bill_period(text)
    results["previous_balance"] = check_previous_balance(text)
    results["current_charges"] = check_current_charges(text)
    results["payments_adjustments"] = check_payments_adjustments(text)
    results["amount_due"] = check_amount_due(text)
    results["due_date_field"] = check_due_date_field(text)

    # Section 4
    results["meter_table"] = check_meter_table_present(text)
    results["actual_or_estimated"] = check_actual_or_estimated_read(text)
    results["usage_kwh"] = check_usage_kwh_value(text)

    # Section 5
    results["energy_charges"] = check_energy_charges(text)
    results["base_charge"] = check_base_charge(text)
    results["tdu_delivery_charges"] = check_tdu_delivery_charges(text)
    results["gross_receipts_tax"] = check_gross_receipts_tax(text)
    results["puc_assessment"] = check_puc_assessment(text)
    results["market_securitization"] = check_market_securitization(text)
    results["total_current_charges"] = check_total_current_charges(text)

    # Section 6
    results["agreement_section"] = check_agreement_section(text)
    results["contract_dates"] = check_contract_dates(text)
    results["expiration_notice"] = check_expiration_notice(text)
    results["average_price_message"] = check_average_price_message(text)
    results["variable_rate_message"] = check_variable_rate_message(text)

    # Section 8
    results["usage_history_heading"] = check_usage_history_heading(text)
    results["usage_history_months"] = check_usage_history_month_labels(text)

    # Section 9
    results["remittance_stub"] = check_remittance_stub_present(text)
    results["stub_reference_number"] = check_stub_reference_number(text)
    results["barcode_qr"] = check_barcode_or_qr_present(text)

    return results


PRINT_ORDER = [
    # Section 1
    "solar", "refer_a_friend", "power_to_choose", "critical_care",
    "things_you_should_know", "unauthorized_charges", "puct_complaint_info", "tdu_contact",
    # Section 2
    "account_number", "service_address_esi_id", "customer_name_billing_address",
    # Section 3
    "bill_number", "bill_date_field", "bill_period", "previous_balance",
    "current_charges", "payments_adjustments", "amount_due", "due_date_field",
    # Section 4
    "meter_table", "actual_or_estimated", "usage_kwh",
    # Section 5
    "energy_charges", "base_charge", "tdu_delivery_charges", "gross_receipts_tax",
    "puc_assessment", "market_securitization", "total_current_charges",
    # Section 6
    "agreement_section", "contract_dates", "expiration_notice",
    "average_price_message", "variable_rate_message",
    # Section 8
    "usage_history_heading", "usage_history_months",
    # Section 9
    "remittance_stub", "stub_reference_number", "barcode_qr",
]


def print_result(results):
    print(f"\n{results['file']}")
    print(f"  Account type: {results['account_type']} | Territory: {results['territory']} | Bill month: {results['bill_month']}")
    for rule in PRINT_ORDER:
        status, detail = results[rule]
        marker = {"PASS": "[PASS]", "FAIL": "[FAIL]", "SKIP": "[SKIP]", "REVIEW": "[REVIEW]"}[status]
        print(f"  {marker} {rule:26} {detail}")


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
        if results is None:
            print(f"\n{fname}  -- SKIPPED (check_bill returned no results, likely a PDF text-extraction issue)")
            continue

        print_result(results)
        all_results.append(results)

    # Summary - counts FAILs across the full check list, not just Section 1
    total = len(all_results)
    fails = [
        (r["file"], rule)
        for r in all_results
        for rule in PRINT_ORDER
        if r[rule][0] == "FAIL"
    ]
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
#
# WHAT STILL NEEDS DOING (honest status, Aug 2026):
#   - Section 7 (Messages & Regulatory Notices) is Section 1 above - already
#     done, just numbered differently between this script and the original
#     9-section checklist from Abby's document.
#   - Section 10 (PDF Display & Formatting) is NOT in this script at all -
#     see the module docstring at the top for why.
#   - Sections 4, 5, 6, 8, 9 are built from ONE real bill (Tara, TNMP).
#     Spot-check at least one Amigo and one Just Energy sample before
#     trusting these results at full batch scale - Sections 2 and 3 both
#     needed real fixes after this same step, so assume these will too.
#   - The average-price-per-kWh CALCULATION (not just message presence)
#     is not implemented - would need numeric extraction and a real
#     formula check, a different task from presence-only checking.
# ---------------------------------------------------------------------------

    

"""
Bill PDF Audit Tool - Phase 1 Rule Checker (Full: Sections 1-9)
=================================================================
Checks a residential/commercial electric bill PDF against the Phase 1
presence-only compliance checklist confirmed with Abby (Billing).

SECTIONS COVERED (text-search / presence checks):
  1. Messages & Regulatory Notices  - stable, validated against 33 real bills
  2. Customer Information           - validated against 1 real bill (Tara)
  3. Billing Summary                - validated against 1 real bill (Tara)
  4. Meter Information              - built from 1 real bill, UNVALIDATED beyond it
  5. Charges & Taxes                - built from 1 real bill, UNVALIDATED beyond it
  6. Agreement Details / Product    - built from 1 real bill, UNVALIDATED beyond it
  8. Usage History                  - built from 1 real bill, UNVALIDATED beyond it
  9. Payment Coupon / Remittance    - built from 1 real bill, UNVALIDATED beyond it

NOT COVERED - SECTION 10 (PDF Display & Formatting):
  Deliberately NOT implemented here. This section (no overlapping/truncated
  text, correct page breaks, fonts/alignment, no blank pages, English +
  Spanish validation) is fundamentally a VISUAL/LAYOUT problem, not a text
  search problem - the same text can extract identically whether it's
  overlapping garbage on the page or perfectly laid out. Faking a text-based
  check here would produce false confidence, which is worse than an honest
  gap. This needs a different approach entirely (e.g. rendering each page to
  an image and doing visual/positional analysis with pdfplumber's word
  coordinates, or a vision-based check) - flag as a separate build, not an
  extension of this script.

IMPORTANT CAVEAT ON SECTIONS 4-6, 8-9:
  Only ONE real bill format (Tara Energy, residential TNMP, commercial
  sample) has been checked by hand so far. Sections 2 and 3 both needed
  real fixes after checking real text - the checklist's assumed wording
  ("Amount Due") didn't match the real bill ("Due Amount"). The same is
  almost certainly true here for Amigo and Just Energy formats. Treat
  every FAIL from Sections 4-6, 8-9 as "needs a manual look", not as a
  confirmed compliance gap, until spot-checked against more real bills.

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
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter

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
}

SOLAR_PHRASE = "residential solar energy"
REFER_PHRASE = "refer a friend"
PTC_PHRASE = "powertochoose.com"
CRITICAL_CARE_PHRASE = "critical care or chronic condition"

CRITICAL_CARE_REQUIRED_MONTHS = {4, 10}  # April, October

MONTH_ABBR = r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)"


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


def _label_then_nearby_value(text, label_pattern, value_pattern, window=150):
    """
    Shared helper: PDF table extraction often puts column headers on one
    line and values on a separate line below (not immediately adjacent),
    so checking label-followed-directly-by-value is too strict. Looks for
    the label, then checks if a matching value appears anywhere within
    `window` characters after it.
    """
    if not text:
        return False
    match = re.search(label_pattern, text)
    if not match:
        return False
    nearby = text[match.end(): match.end() + window]
    return bool(re.search(value_pattern, nearby))


# ---------------------------------------------------------------------------
# SECTION 1 checks - Messages & Regulatory Notices
# each returns (status, detail) where status is "PASS", "FAIL", or "SKIP"
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


def check_things_you_should_know(text):
    if "THINGS YOU SHOULD KNOW ABOUT YOUR BILL" in text.upper():
        return ("PASS", "Required 'THINGS YOU SHOULD KNOW ABOUT YOUR BILL' notice present")
    return ("FAIL", "MISSING required 'THINGS YOU SHOULD KNOW ABOUT YOUR BILL' notice")


def check_unauthorized_charges_notice(text, customer_care_phone):
    text_lower = text.lower()
    if "unauthorized charges" not in text_lower:
        return ("FAIL", "MISSING unauthorized charges notification")
    if customer_care_phone and customer_care_phone in text:
        return ("PASS", f"Unauthorized charges notice present with correct phone number ({customer_care_phone})")
    return ("PASS", "Unauthorized charges notice present (phone number not cross-checked)")


def check_puct_complaint_info(text):
    required_fragments = ["P.O. Box 13326", "78711", "936-7120"]
    missing = [f for f in required_fragments if f not in text]
    if not missing:
        return ("PASS", "PUCT complaint-filing info present and complete")
    return ("FAIL", f"PUCT complaint info incomplete - missing: {', '.join(missing)}")


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
# SECTION 2 checks - Customer Information
# ---------------------------------------------------------------------------

def check_account_number(text):
    """2.2 - Account Number present. Accepts 'Acct #', 'Account Number', etc."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)(account|acct)\.?\s*(number|no\.?|#)\s*[:\-]?\s*\d+"
    if re.search(pattern, text):
        return ("PASS", "Account number field found on bill.")
    return ("FAIL", "No labeled account number found (checked 'Account Number', 'Acct #', 'Acct No.').")


def check_service_address_and_esi_id(text):
    """2.3 / 2.5 combined - 'Service at Premise #' label + 17-digit ESI-ID-format value."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    esiid_format = r"\b10\d{15}\b"
    label_pattern = r"(?i)service\s*(address|at\s*premise)\s*#?\s*[:\-]?"
    has_label = re.search(label_pattern, text)
    has_esiid = re.search(esiid_format, text)
    if has_label and has_esiid:
        return ("PASS", "Service premise field found, with a value matching the expected 17-digit ESI ID format.")
    if has_esiid and not has_label:
        return ("PASS", "A 17-digit ESI-ID-format number was found, though not under a recognized label - verify manually.")
    if has_label and not has_esiid:
        return ("FAIL", "Service address/premise label found, but no ESI-ID-format value nearby - verify manually.")
    return ("FAIL", "No service address, premise number, or ESI ID found.")


def check_customer_name_and_billing_address(text):
    """
    2.1 / 2.4 - HONEST LIMITATION: no label exists for these on real bills.
    Returns REVIEW rather than a false PASS/FAIL.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    top_section = text[:600]
    address_block_pattern = r"[A-Z][a-zA-Z\s]+,\s*TX\s*\d{5}(-\d{4})?"
    if re.search(address_block_pattern, top_section):
        return ("REVIEW", "Address-shaped text found near the top of the bill (likely the customer name/address block) - no label exists to confirm automatically. Manual check needed.")
    return ("FAIL", "No name or address block detected near the top of the bill - worth a manual look, this may be a real gap or a layout this check doesn't cover yet.")


# ---------------------------------------------------------------------------
# SECTION 3 checks - Billing Summary
# ---------------------------------------------------------------------------

def check_bill_number(text):
    """3.1 - Bill Number present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)bill\s*(number|no\.?|#)\s*[:\-]?\s*\d+"
    if re.search(pattern, text):
        return ("PASS", "Bill number field found.")
    return ("FAIL", "No labeled bill number found.")


def check_bill_date_field(text):
    """3.2 - Bill Date present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)bill\s*date\s*[:\-]?\s*\d{1,2}/\d{1,2}/\d{2,4}"
    if re.search(pattern, text):
        return ("PASS", "Bill date field found.")
    return ("FAIL", "No labeled bill date found.")


def check_bill_period(text):
    """3.3 - Bill Period present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)bill\s*period\s*[:\-]?\s*\d{1,2}/\d{1,2}/\d{2,4}"
    if re.search(pattern, text):
        return ("PASS", "Bill period field found.")
    return ("FAIL", "No labeled bill period found.")


def check_previous_balance(text):
    """3.4 - Previous Balance present."""
    if _label_then_nearby_value(text, r"(?i)previous\s*balance", r"\$?-?\d"):
        return ("PASS", "Previous balance field found, with a nearby value.")
    return ("FAIL", "No labeled previous balance found (or no value nearby).")


def check_current_charges(text):
    """3.5 - Current Charges present. Accepts 'Current Charges' or 'New Charges'."""
    if _label_then_nearby_value(text, r"(?i)(current|new)\s*charges", r"\$?-?\d"):
        return ("PASS", "Current/new charges field found, with a nearby value.")
    return ("FAIL", "No labeled current/new charges found (checked both 'Current Charges' and 'New Charges').")


def check_payments_adjustments(text):
    """3.6 - Payments/Adjustments present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)payments\s*/?\s*adj(ustments?)?\.?\s*[:\-]?"
    if re.search(pattern, text):
        return ("PASS", "Payments/Adjustments field found.")
    return ("FAIL", "No labeled payments/adjustments field found.")


def check_amount_due(text):
    """3.7 - Amount Due present. Accepts 'Amount Due' or 'Due Amount'."""
    if _label_then_nearby_value(text, r"(?i)(amount\s*due|due\s*amount)", r"\$?\d"):
        return ("PASS", "Amount due field found, with a nearby value.")
    return ("FAIL", "No labeled amount due found (checked both 'Amount Due' and 'Due Amount').")


def check_due_date_field(text):
    """3.8 - Due Date present."""
    if _label_then_nearby_value(text, r"(?i)due\s*(date|by)", r"\d{1,2}/\d{1,2}/\d{2,4}"):
        return ("PASS", "Due date field found, with a nearby value.")
    return ("FAIL", "No labeled due date found (or no date value nearby).")


# ---------------------------------------------------------------------------
# SECTION 4 checks - Meter Information
# Built from real bill's meter table: "Meter | Type | Dates | Curr. Rd |
# Prev. Rd | Mult | Usage" header row, e.g. "348197676 ACT 03/23-04/22
# 23430 22904 1 526.00". UNVALIDATED against Amigo/Just Energy formats.
# ---------------------------------------------------------------------------

def check_meter_table_present(text):
    """
    4.1-4.6 combined - checks that the meter reading table itself is
    present (Meter/Type/Dates/Curr Rd/Prev Rd/Usage headers together).
    Combined into one check since these headers sit in one table row on
    the real bill checked - splitting into 6 separate checks would likely
    just fail identically for all 6 if the table format differs even
    slightly, giving false precision.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    required_headers = ["meter", "type", "curr", "prev", "usage"]
    lower = text.lower()
    missing = [h for h in required_headers if h not in lower]
    if not missing:
        return ("PASS", "Meter reading table headers found (Meter/Type/Curr Rd/Prev Rd/Usage).")
    return ("FAIL", f"Meter table appears incomplete or uses different labels - missing: {', '.join(missing)}. Verify manually.")


def check_actual_or_estimated_read(text):
    """
    4.2 - Actual vs. Estimated read indicator. Real bill uses 'ACT' as a
    table cell value, not a full word - checking for that short code plus
    the long-form alternates in case other brands spell it out.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)\b(ACT|EST|Actual|Estimated)\b"
    if re.search(pattern, text):
        return ("PASS", "Actual/Estimated read indicator found.")
    return ("FAIL", "No Actual/Estimated read indicator found (checked 'ACT', 'EST', 'Actual', 'Estimated').")


def check_usage_kwh_value(text):
    """4.6 - Usage (kWh) value present, near a 'Usage' label."""
    if _label_then_nearby_value(text, r"(?i)usage", r"[\d,]+\.\d{2}"):
        return ("PASS", "Usage value found near a 'Usage' label.")
    return ("FAIL", "No usage value found near a 'Usage' label - verify manually.")


# ---------------------------------------------------------------------------
# SECTION 5 checks - Charges & Taxes
# Built from real bill's charge line items: Base Charge, [Plan Name] Energy
# Plan, Market Securitization Debt Fin., ERCOT Admin Fee, TDSP Delivery
# Charges, City Tax, PUC Assessment, State Tax, Gross Receipt Reimb.
# NOTE: the average-price-per-kWh CALCULATION (compute cents/kWh excluding
# tax, compare to the printed value) is NOT implemented here - that is a
# numeric validation task, a different complexity tier from a presence
# check, and doing it wrong with unverified assumptions would be worse
# than leaving it as an explicit open item.
# ---------------------------------------------------------------------------

def check_energy_charges(text):
    """
    5.1 - Energy charges/rate/amount line item present. Brands label this
    differently: Tara/Amigo call it '[Plan Name] Energy Plan', Just
    Energy calls it 'Energy Charges' explicitly. Checking for either.
    """
    pattern = r"(?i)energy\s*(charges|plan)"
    if _label_then_nearby_value(text, pattern, r"\$?-?\d"):
        return ("PASS", "Energy charges/plan line item found, with a nearby value.")
    return ("FAIL", "No energy charges/plan line item found (checked 'Energy Charges' and '... Energy Plan').")


def check_base_charge(text):
    """
    5.2 - Base Charge line item present.
    NOTE: a real Amigo commercial bill checked has NO separate Base
    Charge line at all (likely folded into the plan/energy charge line
    instead) - a FAIL here may be a genuine brand/account-type
    difference, not a missing-field error. Verify manually before
    treating this as a compliance gap.
    """
    if _label_then_nearby_value(text, r"(?i)base\s*charge", r"\$?\d"):
        return ("PASS", "Base Charge line item found, with a nearby value.")
    return ("FAIL", "No 'Base Charge' line item found - may be genuinely absent on this brand/account type rather than missing, verify manually.")


def check_tdu_delivery_charges(text):
    """5.3 - TDU/TDSP delivery (pass-through) charges present."""
    pattern = r"(?i)(tdsp|tdu)\s*delivery"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "TDU/TDSP delivery charges found, with a nearby value.")
    return ("FAIL", "No TDU/TDSP delivery charges line item found.")


def check_gross_receipts_tax(text):
    """5.4 - Gross receipts tax/reimbursement present."""
    pattern = r"(?i)gross\s*receipt"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "Gross receipts tax/reimbursement line item found.")
    return ("FAIL", "No gross receipts tax/reimbursement line item found.")


def check_puc_assessment(text):
    """5.5 - PUC assessment present."""
    pattern = r"(?i)puc\s*assessment"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "PUC assessment line item found, with a nearby value.")
    return ("FAIL", "No PUC assessment line item found.")


def check_market_securitization(text):
    """5.6 - Market securitization charge present."""
    pattern = r"(?i)market\s*securitization"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "Market securitization line item found, with a nearby value.")
    return ("FAIL", "No market securitization line item found - note this may be brand-specific, not all REPs itemize this separately.")


def check_total_current_charges(text):
    """
    5.1/5.8 combined - the overall 'Total Current Charges' or
    'Total Amount Due' rollup line is present (energy charges + all
    line items summed).
    """
    pattern = r"(?i)total\s*(current\s*charges|amount\s*due)"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "Total charges/amount due rollup line found.")
    return ("FAIL", "No 'Total Current Charges' or 'Total Amount Due' rollup line found.")


# ---------------------------------------------------------------------------
# SECTION 6 checks - Agreement Details / Product Info
# Built from real bill: "Agreement Details" heading, date-range + plan name
# line, "The average price you paid for electricity this month is X¢ per
# kWh." message, "You have a valid contract until MM/DD/YYYY" message.
# variable_rate check is a best-guess phrase, NOT confirmed against a real
# variable-rate bill yet (the one bill checked has a fixed-rate plan).
# ---------------------------------------------------------------------------

def check_agreement_section(text):
    """6.1 - 'Agreement Details' section heading present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    if re.search(r"(?i)agreement\s*details", text):
        return ("PASS", "Agreement Details section heading found.")
    return ("FAIL", "No 'Agreement Details' section heading found.")


def check_contract_dates(text):
    """6.3 - Contract start/end or bill-cycle date range near Agreement Details."""
    if _label_then_nearby_value(text, r"(?i)agreement\s*details", r"\d{1,2}/\d{1,2}/\d{2,4}\s*-\s*\d{1,2}/\d{1,2}/\d{2,4}"):
        return ("PASS", "A date range was found near the Agreement Details section.")
    return ("FAIL", "No date range found near Agreement Details - verify manually.")


def check_expiration_notice(text):
    """
    6.4 - Contract expiration notice present.
    Accepts both word orders seen across brands: Tara/Amigo say "valid
    contract until MM/DD/YYYY", Just Energy says "contract valid until
    MM/DD/YYYY" - same information, swapped word order.
    """
    pattern = r"(?i)(valid\s*contract\s*until|contract\s*valid\s*until)\s*\d{1,2}/\d{1,2}/\d{2,4}"
    if re.search(pattern, text):
        return ("PASS", "Contract expiration notice found.")
    return ("FAIL", "No contract expiration notice found (checked both 'valid contract until' and 'contract valid until' wordings).")


def check_average_price_message(text):
    """6.5 - Average price per kWh message present (text only, not the calculation)."""
    pattern = r"(?i)average\s*price\s*you\s*paid\s*for\s*electricity"
    if re.search(pattern, text):
        return ("PASS", "Average price message found. NOTE: this only confirms the message text is present, not that the printed cents/kWh value is mathematically correct.")
    return ("FAIL", "No average price per kWh message found.")


def check_variable_rate_message(text):
    """
    6.6 - Variable rate disclosure message. UNCONFIRMED wording - the one
    real bill checked has a fixed-rate plan and doesn't show this message,
    so this pattern is a best guess, not verified against a real example.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)variable\s*rate"
    if re.search(pattern, text):
        return ("PASS", "A 'variable rate' phrase was found - verify this matches the actual required disclosure wording.")
    return ("SKIP", "No 'variable rate' phrase found - UNCONFIRMED whether this bill is even a variable-rate plan; this check hasn't been validated against a real variable-rate bill yet.")


# ---------------------------------------------------------------------------
# SECTION 8 checks - Usage History
# Built from real bill: "Usage history (KWH)" chart heading, with month
# abbreviations (Apr, May, Jun...) printed as axis labels below the chart.
# ---------------------------------------------------------------------------

def check_usage_history_heading(text):
    """8.1 - 'Usage history (KWH)' chart heading present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    if re.search(r"(?i)usage\s*history", text):
        return ("PASS", "Usage history chart heading found.")
    return ("FAIL", "No 'Usage history' chart heading found.")


def check_usage_history_month_labels(text):
    """
    8.2/8.3 - Historical monthly values / graph month labels. Checks for
    at least several 3-letter month abbreviations near the usage history
    heading, as a proxy for the chart's axis labels having extracted as
    text (charts/images may not always extract this way - a real gap
    here could also just mean the chart is an embedded image with no
    text layer, which this check can't distinguish from a missing chart).
    """
    match = re.search(r"(?i)usage\s*history", text)
    if not match:
        return ("FAIL", "No 'Usage history' section found to check for month labels.")
    nearby = text[match.end(): match.end() + 400]
    months_found = re.findall(MONTH_ABBR, nearby)
    if len(months_found) >= 6:
        return ("PASS", f"Found {len(months_found)} month labels near the usage history chart.")
    return ("FAIL", f"Only found {len(months_found)} month labels near usage history (expected ~12) - verify manually, chart may be an image with no text layer.")


# ---------------------------------------------------------------------------
# SECTION 9 checks - Payment Coupon / Remittance Stub
# Built from real bill: "Please return this portion with your payment"
# divider text, a long numeric string under the remittance barcode area,
# and a "Do Not Pay - AutoPay" flag seen on the autopay sample checked.
# Barcode/QR presence is explicitly NOT checked - see note below.
# ---------------------------------------------------------------------------

def check_remittance_stub_present(text):
    """9.1 - Return-payment / remittance stub section present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)please\s*return\s*this\s*portion\s*with\s*your\s*payment"
    if re.search(pattern, text):
        return ("PASS", "Remittance stub divider text found ('Please return this portion with your payment').")
    return ("FAIL", "No remittance stub divider text found - verify manually, wording may differ by brand.")


def check_stub_reference_number(text):
    """
    9.8 - Long reference/routing number on the stub (OCR line under the
    barcode). Real bill showed a 30+ digit string. This is a weak proxy -
    a false PASS is possible if an unrelated long digit string appears
    elsewhere on the page.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"\b\d{20,}\b"
    if re.search(pattern, text):
        return ("PASS", "A long reference/routing number (20+ digits) was found - likely the stub OCR line, but not position-verified.")
    return ("FAIL", "No long reference/routing number found on the stub.")


def check_barcode_or_qr_present(text):
    """
    9.7 - Barcode/QR code presence. NOT CHECKABLE via text extraction - a
    barcode/QR is an image, not text, so pdfplumber's text layer will
    never show it either way. This always returns SKIP rather than a
    false PASS or FAIL. Confirming this needs an image-based check
    (e.g. counting embedded images on the stub page), which is a
    different kind of check from everything else in this script.
    """
    return ("SKIP", "Barcode/QR presence cannot be checked via text extraction - needs an image-based check, not implemented here.")


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

    # Section 1
    results["solar"] = check_solar(text, account_type)
    results["refer_a_friend"] = check_refer_a_friend(text, account_type)
    results["power_to_choose"] = check_power_to_choose(text, account_type)
    results["critical_care"] = check_critical_care(text, bill_month)
    results["things_you_should_know"] = check_things_you_should_know(text)
    results["unauthorized_charges"] = check_unauthorized_charges_notice(text, None)
    results["puct_complaint_info"] = check_puct_complaint_info(text)
    results["tdu_contact"] = check_tdu_contact(text, territory)

    # Section 2
    results["account_number"] = check_account_number(text)
    results["service_address_esi_id"] = check_service_address_and_esi_id(text)
    results["customer_name_billing_address"] = check_customer_name_and_billing_address(text)

    # Section 3
    results["bill_number"] = check_bill_number(text)
    results["bill_date_field"] = check_bill_date_field(text)
    results["bill_period"] = check_bill_period(text)
    results["previous_balance"] = check_previous_balance(text)
    results["current_charges"] = check_current_charges(text)
    results["payments_adjustments"] = check_payments_adjustments(text)
    results["amount_due"] = check_amount_due(text)
    results["due_date_field"] = check_due_date_field(text)

    # Section 4
    results["meter_table"] = check_meter_table_present(text)
    results["actual_or_estimated"] = check_actual_or_estimated_read(text)
    results["usage_kwh"] = check_usage_kwh_value(text)

    # Section 5
    results["energy_charges"] = check_energy_charges(text)
    results["base_charge"] = check_base_charge(text)
    results["tdu_delivery_charges"] = check_tdu_delivery_charges(text)
    results["gross_receipts_tax"] = check_gross_receipts_tax(text)
    results["puc_assessment"] = check_puc_assessment(text)
    results["market_securitization"] = check_market_securitization(text)
    results["total_current_charges"] = check_total_current_charges(text)

    # Section 6
    results["agreement_section"] = check_agreement_section(text)
    results["contract_dates"] = check_contract_dates(text)
    results["expiration_notice"] = check_expiration_notice(text)
    results["average_price_message"] = check_average_price_message(text)
    results["variable_rate_message"] = check_variable_rate_message(text)

    # Section 8
    results["usage_history_heading"] = check_usage_history_heading(text)
    results["usage_history_months"] = check_usage_history_month_labels(text)

    # Section 9
    results["remittance_stub"] = check_remittance_stub_present(text)
    results["stub_reference_number"] = check_stub_reference_number(text)
    results["barcode_qr"] = check_barcode_or_qr_present(text)

    return results


PRINT_ORDER = [
    # Section 1
    "solar", "refer_a_friend", "power_to_choose", "critical_care",
    "things_you_should_know", "unauthorized_charges", "puct_complaint_info", "tdu_contact",
    # Section 2
    "account_number", "service_address_esi_id", "customer_name_billing_address",
    # Section 3
    "bill_number", "bill_date_field", "bill_period", "previous_balance",
    "current_charges", "payments_adjustments", "amount_due", "due_date_field",
    # Section 4
    "meter_table", "actual_or_estimated", "usage_kwh",
    # Section 5
    "energy_charges", "base_charge", "tdu_delivery_charges", "gross_receipts_tax",
    "puc_assessment", "market_securitization", "total_current_charges",
    # Section 6
    "agreement_section", "contract_dates", "expiration_notice",
    "average_price_message", "variable_rate_message",
    # Section 8
    "usage_history_heading", "usage_history_months",
    # Section 9
    "remittance_stub", "stub_reference_number", "barcode_qr",
]


def print_result(results):
    print(f"\n{results['file']}")
    print(f"  Account type: {results['account_type']} | Territory: {results['territory']} | Bill month: {results['bill_month']}")
    for rule in PRINT_ORDER:
        status, detail = results[rule]
        marker = {"PASS": "[PASS]", "FAIL": "[FAIL]", "SKIP": "[SKIP]", "REVIEW": "[REVIEW]"}[status]
        print(f"  {marker} {rule:26} {detail}")


# Plain-English column headers for the Excel export - non-technical readers
# (Abby, Sif) shouldn't have to know what "esi_id" or "tdu_contact" means.
RULE_LABELS = {
    "solar": "Solar Message",
    "refer_a_friend": "Refer a Friend Message",
    "power_to_choose": "Power to Choose Message",
    "critical_care": "Critical Care Message",
    "things_you_should_know": "Things You Should Know Notice",
    "unauthorized_charges": "Unauthorized Charges Notice",
    "puct_complaint_info": "PUCT Complaint Info",
    "tdu_contact": "TDU Emergency Contact",
    "account_number": "Account Number",
    "service_address_esi_id": "Service Address / ESI ID",
    "customer_name_billing_address": "Customer Name / Billing Address",
    "bill_number": "Bill Number",
    "bill_date_field": "Bill Date",
    "bill_period": "Bill Period",
    "previous_balance": "Previous Balance",
    "current_charges": "Current Charges",
    "payments_adjustments": "Payments / Adjustments",
    "amount_due": "Amount Due",
    "due_date_field": "Due Date",
    "meter_table": "Meter Reading Table",
    "actual_or_estimated": "Actual / Estimated Read",
    "usage_kwh": "Usage (kWh)",
    "energy_charges": "Energy Charges",
    "base_charge": "Base Charge",
    "tdu_delivery_charges": "TDU Delivery Charges",
    "gross_receipts_tax": "Gross Receipts Tax",
    "puc_assessment": "PUC Assessment",
    "market_securitization": "Market Securitization",
    "total_current_charges": "Total Current Charges",
    "agreement_section": "Agreement Details Section",
    "contract_dates": "Contract Dates",
    "expiration_notice": "Contract Expiration Notice",
    "average_price_message": "Average Price Message",
    "variable_rate_message": "Variable Rate Message",
    "usage_history_heading": "Usage History Heading",
    "usage_history_months": "Usage History Month Labels",
    "remittance_stub": "Remittance Stub",
    "stub_reference_number": "Stub Reference Number",
    "barcode_qr": "Barcode / QR Code",
}

STATUS_FILL = {
    "PASS": PatternFill(start_color="C6EFCE", end_color="C6EFCE", fill_type="solid"),   # green
    "FAIL": PatternFill(start_color="FFC7CE", end_color="FFC7CE", fill_type="solid"),   # red
    "REVIEW": PatternFill(start_color="FFEB9C", end_color="FFEB9C", fill_type="solid"), # yellow
    "SKIP": PatternFill(start_color="D9D9D9", end_color="D9D9D9", fill_type="solid"),   # gray
}
STATUS_FONT = {
    "PASS": Font(name="Arial", color="006100"),
    "FAIL": Font(name="Arial", color="9C0006"),
    "REVIEW": Font(name="Arial", color="9C6500"),
    "SKIP": Font(name="Arial", color="595959"),
}


def write_excel_report(all_results, output_path):
    """
    Writes a plain-English Excel report of every bill's check results -
    for Abby, Sif, or anyone who needs to review results without running
    Python or reading a terminal. Same precedent as the Missed AWT
    Interval Report built for WFM: a spreadsheet Abby can open and filter
    herself, not a script someone has to run for her.

    Sheet 1 "Results" - one row per bill, one column per check, colored
    PASS/FAIL/REVIEW/SKIP with the plain-English reason in the cell,
    autofilter enabled on the header row so she can filter to FAILs.

    Sheet 2 "Summary" - one row per check, counting how many bills
    passed/failed/etc, sorted so the most-failing checks are easy to spot
    without scrolling the raw data.
    """
    wb = Workbook()

    # ---------------- Sheet 1: Results ----------------
    ws = wb.active
    ws.title = "Results"

    header_font = Font(name="Arial", bold=True, color="FFFFFF")
    header_fill = PatternFill(start_color="004061", end_color="004061", fill_type="solid")

    headers = ["File", "Account Type", "Territory", "Bill Month", "Bill Year"] + [RULE_LABELS[r] for r in PRINT_ORDER]
    for col_idx, header in enumerate(headers, start=1):
        cell = ws.cell(row=1, column=col_idx, value=header)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(wrap_text=True, vertical="center")

    for row_idx, results in enumerate(all_results, start=2):
        ws.cell(row=row_idx, column=1, value=results["file"]).font = Font(name="Arial")
        ws.cell(row=row_idx, column=2, value=results["account_type"]).font = Font(name="Arial")
        ws.cell(row=row_idx, column=3, value=results["territory"]).font = Font(name="Arial")
        ws.cell(row=row_idx, column=4, value=results["bill_month"]).font = Font(name="Arial")
        ws.cell(row=row_idx, column=5, value=results["bill_year"]).font = Font(name="Arial")

        for col_offset, rule in enumerate(PRINT_ORDER):
            status, detail = results[rule]
            cell = ws.cell(row=row_idx, column=6 + col_offset, value=f"{status}: {detail}")
            cell.fill = STATUS_FILL[status]
            cell.font = STATUS_FONT[status]
            cell.alignment = Alignment(wrap_text=True, vertical="top")

    ws.freeze_panes = "F2"  # freeze header row + the 5 identifying columns
    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}{len(all_results) + 1}"
    ws.column_dimensions["A"].width = 45
    for col_idx in range(2, 6):
        ws.column_dimensions[get_column_letter(col_idx)].width = 14
    for col_idx in range(6, len(headers) + 1):
        ws.column_dimensions[get_column_letter(col_idx)].width = 32
    ws.row_dimensions[1].height = 45

    # ---------------- Sheet 2: Summary ----------------
    ws2 = wb.create_sheet("Summary")
    ws2.cell(row=1, column=1, value="Bill PDF Audit - Summary").font = Font(name="Arial", bold=True, size=14)
    ws2.cell(row=2, column=1, value=f"Total bills checked: {len(all_results)}").font = Font(name="Arial")

    summary_headers = ["Check", "Passed", "Failed", "Needs Review", "Skipped"]
    for col_idx, header in enumerate(summary_headers, start=1):
        cell = ws2.cell(row=4, column=col_idx, value=header)
        cell.font = header_font
        cell.fill = header_fill

    counts = []
    for rule in PRINT_ORDER:
        passed = sum(1 for r in all_results if r[rule][0] == "PASS")
        failed = sum(1 for r in all_results if r[rule][0] == "FAIL")
        review = sum(1 for r in all_results if r[rule][0] == "REVIEW")
        skipped = sum(1 for r in all_results if r[rule][0] == "SKIP")
        counts.append((RULE_LABELS[rule], passed, failed, review, skipped))

    # Sort so the checks with the most failures show up first - the ones
    # most worth Abby's attention, not buried alphabetically.
    counts.sort(key=lambda row: row[2], reverse=True)

    for row_idx, (label, passed, failed, review, skipped) in enumerate(counts, start=5):
        ws2.cell(row=row_idx, column=1, value=label).font = Font(name="Arial")
        fail_cell = ws2.cell(row=row_idx, column=3, value=failed)
        fail_cell.font = Font(name="Arial", bold=(failed > 0), color="9C0006" if failed > 0 else "000000")
        ws2.cell(row=row_idx, column=2, value=passed).font = Font(name="Arial")
        ws2.cell(row=row_idx, column=4, value=review).font = Font(name="Arial")
        ws2.cell(row=row_idx, column=5, value=skipped).font = Font(name="Arial")

    ws2.column_dimensions["A"].width = 34
    for col in ["B", "C", "D", "E"]:
        ws2.column_dimensions[col].width = 14

    wb.save(output_path)
    print(f"\nExcel report written to: {output_path}")


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


def run_batch(folder, manifest_path=None, excel_path=None):
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
        if results is None:
            print(f"\n{fname}  -- SKIPPED (check_bill returned no results, likely a PDF text-extraction issue)")
            continue

        print_result(results)
        all_results.append(results)

    # Summary - counts FAILs across the full check list, not just Section 1
    total = len(all_results)
    fails = [
        (r["file"], rule)
        for r in all_results
        for rule in PRINT_ORDER
        if r[rule][0] == "FAIL"
    ]
    print(f"\n{'='*60}")
    print(f"SUMMARY: {total} bills checked, {len(fails)} rule failures found")
    print(f"{'='*60}")

    if excel_path and all_results:
        write_excel_report(all_results, excel_path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Bill PDF Audit Tool - Phase 1 rule checker")
    parser.add_argument("pdf", nargs="?", help="Path to a single PDF to check")
    parser.add_argument("--account-type", choices=["residential", "commercial"], help="Account type for single-file mode")
    parser.add_argument("--territory", help="Utility territory for single-file mode (Centerpoint/Oncor/AEP/TNMP/Lubbock)")
    parser.add_argument("--batch", help="Folder to batch-check (recursively finds all PDFs)")
    parser.add_argument("--manifest", help="Optional CSV with columns: filename,account_type,territory")
    parser.add_argument("--excel", help="Optional path to write an Excel report (e.g. bill_audit_report.xlsx) - for non-technical review (Abby, Sif), same pattern as the Missed AWT Interval Report")
    args = parser.parse_args()

    if args.batch:
        run_batch(args.batch, args.manifest, args.excel)
    elif args.pdf:
        if not args.account_type or not args.territory:
            print("Single-file mode requires --account-type and --territory")
            sys.exit(1)
        results = check_bill(args.pdf, args.account_type, args.territory)
        print_result(results)
        if args.excel:
            write_excel_report([results], args.excel)
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
#
# WHAT STILL NEEDS DOING (honest status, Aug 2026):
#   - Section 7 (Messages & Regulatory Notices) is Section 1 above - already
#     done, just numbered differently between this script and the original
#     9-section checklist from Abby's document.
#   - Section 10 (PDF Display & Formatting) is NOT in this script at all -
#     see the module docstring at the top for why.
#   - Sections 4, 5, 6, 8, 9 are built from ONE real bill (Tara, TNMP).
#     Spot-check at least one Amigo and one Just Energy sample before
#     trusting these results at full batch scale - Sections 2 and 3 both
#     needed real fixes after this same step, so assume these will too.
#   - The average-price-per-kWh CALCULATION (not just message presence)
#     is not implemented - would need numeric extraction and a real
#     formula check, a different task from presence-only checking.
# ---------------------------------------------------------------------------






"""
Bill PDF Audit Tool - Phase 1 Rule Checker (Full: Sections 1-9)
=================================================================
Checks a residential/commercial electric bill PDF against the Phase 1
presence-only compliance checklist confirmed with Abby (Billing).

SECTIONS COVERED (text-search / presence checks):
  1. Messages & Regulatory Notices  - stable, validated against 33 real bills
  2. Customer Information           - validated against 1 real bill (Tara)
  3. Billing Summary                - validated against 1 real bill (Tara)
  4. Meter Information              - built from 1 real bill, UNVALIDATED beyond it
  5. Charges & Taxes                - built from 1 real bill, UNVALIDATED beyond it
  6. Agreement Details / Product    - built from 1 real bill, UNVALIDATED beyond it
  8. Usage History                  - built from 1 real bill, UNVALIDATED beyond it
  9. Payment Coupon / Remittance    - built from 1 real bill, UNVALIDATED beyond it

NOT COVERED - SECTION 10 (PDF Display & Formatting):
  Deliberately NOT implemented here. This section (no overlapping/truncated
  text, correct page breaks, fonts/alignment, no blank pages, English +
  Spanish validation) is fundamentally a VISUAL/LAYOUT problem, not a text
  search problem - the same text can extract identically whether it's
  overlapping garbage on the page or perfectly laid out. Faking a text-based
  check here would produce false confidence, which is worse than an honest
  gap. This needs a different approach entirely (e.g. rendering each page to
  an image and doing visual/positional analysis with pdfplumber's word
  coordinates, or a vision-based check) - flag as a separate build, not an
  extension of this script.

IMPORTANT CAVEAT ON SECTIONS 4-6, 8-9:
  Only ONE real bill format (Tara Energy, residential TNMP, commercial
  sample) has been checked by hand so far. Sections 2 and 3 both needed
  real fixes after checking real text - the checklist's assumed wording
  ("Amount Due") didn't match the real bill ("Due Amount"). The same is
  almost certainly true here for Amigo and Just Energy formats. Treat
  every FAIL from Sections 4-6, 8-9 as "needs a manual look", not as a
  confirmed compliance gap, until spot-checked against more real bills.

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
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter

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
}

SOLAR_PHRASE = "residential solar energy"
REFER_PHRASE = "refer a friend"
PTC_PHRASE = "powertochoose.com"
CRITICAL_CARE_PHRASE = "critical care or chronic condition"

CRITICAL_CARE_REQUIRED_MONTHS = {4, 10}  # April, October

MONTH_ABBR = r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)"


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


def _label_then_nearby_value(text, label_pattern, value_pattern, window=150):
    """
    Shared helper: PDF table extraction often puts column headers on one
    line and values on a separate line below (not immediately adjacent),
    so checking label-followed-directly-by-value is too strict. Looks for
    the label, then checks if a matching value appears anywhere within
    `window` characters after it.
    """
    if not text:
        return False
    match = re.search(label_pattern, text)
    if not match:
        return False
    nearby = text[match.end(): match.end() + window]
    return bool(re.search(value_pattern, nearby))


# ---------------------------------------------------------------------------
# SECTION 1 checks - Messages & Regulatory Notices
# each returns (status, detail) where status is "PASS", "FAIL", or "SKIP"
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


def check_things_you_should_know(text):
    if "THINGS YOU SHOULD KNOW ABOUT YOUR BILL" in text.upper():
        return ("PASS", "Required 'THINGS YOU SHOULD KNOW ABOUT YOUR BILL' notice present")
    return ("FAIL", "MISSING required 'THINGS YOU SHOULD KNOW ABOUT YOUR BILL' notice")


def check_unauthorized_charges_notice(text, customer_care_phone):
    text_lower = text.lower()
    if "unauthorized charges" not in text_lower:
        return ("FAIL", "MISSING unauthorized charges notification")
    if customer_care_phone and customer_care_phone in text:
        return ("PASS", f"Unauthorized charges notice present with correct phone number ({customer_care_phone})")
    return ("PASS", "Unauthorized charges notice present (phone number not cross-checked)")


def check_puct_complaint_info(text):
    required_fragments = ["P.O. Box 13326", "78711", "936-7120"]
    missing = [f for f in required_fragments if f not in text]
    if not missing:
        return ("PASS", "PUCT complaint-filing info present and complete")
    return ("FAIL", f"PUCT complaint info incomplete - missing: {', '.join(missing)}")


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
# SECTION 2 checks - Customer Information
# ---------------------------------------------------------------------------

def check_account_number(text):
    """2.2 - Account Number present. Accepts 'Acct #', 'Account Number', etc."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)(account|acct)\.?\s*(number|no\.?|#)\s*[:\-]?\s*\d+"
    if re.search(pattern, text):
        return ("PASS", "Account number field found on bill.")
    return ("FAIL", "No labeled account number found (checked 'Account Number', 'Acct #', 'Acct No.').")


def check_service_address_and_esi_id(text):
    """2.3 / 2.5 combined - 'Service at Premise #' label + 17-digit ESI-ID-format value."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    esiid_format = r"\b10\d{15}\b"
    label_pattern = r"(?i)service\s*(address|at\s*premise)\s*#?\s*[:\-]?"
    has_label = re.search(label_pattern, text)
    has_esiid = re.search(esiid_format, text)
    if has_label and has_esiid:
        return ("PASS", "Service premise field found, with a value matching the expected 17-digit ESI ID format.")
    if has_esiid and not has_label:
        return ("PASS", "A 17-digit ESI-ID-format number was found, though not under a recognized label - verify manually.")
    if has_label and not has_esiid:
        return ("FAIL", "Service address/premise label found, but no ESI-ID-format value nearby - verify manually.")
    return ("FAIL", "No service address, premise number, or ESI ID found.")


def check_customer_name_and_billing_address(text):
    """
    2.1 / 2.4 - HONEST LIMITATION: no label exists for these on real bills.
    Returns REVIEW rather than a false PASS/FAIL.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    top_section = text[:600]
    address_block_pattern = r"[A-Z][a-zA-Z\s]+,\s*TX\s*\d{5}(-\d{4})?"
    if re.search(address_block_pattern, top_section):
        return ("REVIEW", "Address-shaped text found near the top of the bill (likely the customer name/address block) - no label exists to confirm automatically. Manual check needed.")
    return ("FAIL", "No name or address block detected near the top of the bill - worth a manual look, this may be a real gap or a layout this check doesn't cover yet.")


# ---------------------------------------------------------------------------
# SECTION 3 checks - Billing Summary
# ---------------------------------------------------------------------------

def check_bill_number(text):
    """3.1 - Bill Number present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)bill\s*(number|no\.?|#)\s*[:\-]?\s*\d+"
    if re.search(pattern, text):
        return ("PASS", "Bill number field found.")
    return ("FAIL", "No labeled bill number found.")


def check_bill_date_field(text):
    """3.2 - Bill Date present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)bill\s*date\s*[:\-]?\s*\d{1,2}/\d{1,2}/\d{2,4}"
    if re.search(pattern, text):
        return ("PASS", "Bill date field found.")
    return ("FAIL", "No labeled bill date found.")


def check_bill_period(text):
    """3.3 - Bill Period present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)bill\s*period\s*[:\-]?\s*\d{1,2}/\d{1,2}/\d{2,4}"
    if re.search(pattern, text):
        return ("PASS", "Bill period field found.")
    return ("FAIL", "No labeled bill period found.")


def check_previous_balance(text):
    """3.4 - Previous Balance present."""
    if _label_then_nearby_value(text, r"(?i)previous\s*balance", r"\$?-?\d"):
        return ("PASS", "Previous balance field found, with a nearby value.")
    return ("FAIL", "No labeled previous balance found (or no value nearby).")


def check_current_charges(text):
    """3.5 - Current Charges present. Accepts 'Current Charges' or 'New Charges'."""
    if _label_then_nearby_value(text, r"(?i)(current|new)\s*charges", r"\$?-?\d"):
        return ("PASS", "Current/new charges field found, with a nearby value.")
    return ("FAIL", "No labeled current/new charges found (checked both 'Current Charges' and 'New Charges').")


def check_payments_adjustments(text):
    """3.6 - Payments/Adjustments present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)payments\s*/?\s*adj(ustments?)?\.?\s*[:\-]?"
    if re.search(pattern, text):
        return ("PASS", "Payments/Adjustments field found.")
    return ("FAIL", "No labeled payments/adjustments field found.")


def check_amount_due(text):
    """3.7 - Amount Due present. Accepts 'Amount Due' or 'Due Amount'."""
    if _label_then_nearby_value(text, r"(?i)(amount\s*due|due\s*amount)", r"\$?\d"):
        return ("PASS", "Amount due field found, with a nearby value.")
    return ("FAIL", "No labeled amount due found (checked both 'Amount Due' and 'Due Amount').")


def check_due_date_field(text):
    """3.8 - Due Date present."""
    if _label_then_nearby_value(text, r"(?i)due\s*(date|by)", r"\d{1,2}/\d{1,2}/\d{2,4}"):
        return ("PASS", "Due date field found, with a nearby value.")
    return ("FAIL", "No labeled due date found (or no date value nearby).")


# ---------------------------------------------------------------------------
# SECTION 4 checks - Meter Information
# Built from real bill's meter table: "Meter | Type | Dates | Curr. Rd |
# Prev. Rd | Mult | Usage" header row, e.g. "348197676 ACT 03/23-04/22
# 23430 22904 1 526.00". UNVALIDATED against Amigo/Just Energy formats.
# ---------------------------------------------------------------------------

def check_meter_table_present(text):
    """
    4.1-4.6 combined - checks that the meter reading table itself is
    present (Meter/Type/Dates/Curr Rd/Prev Rd/Usage headers together).
    Combined into one check since these headers sit in one table row on
    the real bill checked - splitting into 6 separate checks would likely
    just fail identically for all 6 if the table format differs even
    slightly, giving false precision.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    required_headers = ["meter", "type", "curr", "prev", "usage"]
    lower = text.lower()
    missing = [h for h in required_headers if h not in lower]
    if not missing:
        return ("PASS", "Meter reading table headers found (Meter/Type/Curr Rd/Prev Rd/Usage).")
    return ("FAIL", f"Meter table appears incomplete or uses different labels - missing: {', '.join(missing)}. Verify manually.")


def check_actual_or_estimated_read(text):
    """
    4.2 - Actual vs. Estimated read indicator. Real bill uses 'ACT' as a
    table cell value, not a full word - checking for that short code plus
    the long-form alternates in case other brands spell it out.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)\b(ACT|EST|Actual|Estimated)\b"
    if re.search(pattern, text):
        return ("PASS", "Actual/Estimated read indicator found.")
    return ("FAIL", "No Actual/Estimated read indicator found (checked 'ACT', 'EST', 'Actual', 'Estimated').")


def check_usage_kwh_value(text):
    """4.6 - Usage (kWh) value present, near a 'Usage' label."""
    if _label_then_nearby_value(text, r"(?i)usage", r"[\d,]+\.\d{2}"):
        return ("PASS", "Usage value found near a 'Usage' label.")
    return ("FAIL", "No usage value found near a 'Usage' label - verify manually.")


# ---------------------------------------------------------------------------
# SECTION 5 checks - Charges & Taxes
# Built from real bill's charge line items: Base Charge, [Plan Name] Energy
# Plan, Market Securitization Debt Fin., ERCOT Admin Fee, TDSP Delivery
# Charges, City Tax, PUC Assessment, State Tax, Gross Receipt Reimb.
# NOTE: the average-price-per-kWh CALCULATION (compute cents/kWh excluding
# tax, compare to the printed value) is NOT implemented here - that is a
# numeric validation task, a different complexity tier from a presence
# check, and doing it wrong with unverified assumptions would be worse
# than leaving it as an explicit open item.
# ---------------------------------------------------------------------------

def check_energy_charges(text):
    """
    5.1 - Energy charges/rate/amount line item present. Brands label this
    differently: Tara/Amigo call it '[Plan Name] Energy Plan', Just
    Energy calls it 'Energy Charges' explicitly. Checking for either.
    """
    pattern = r"(?i)energy\s*(charges|plan)"
    if _label_then_nearby_value(text, pattern, r"\$?-?\d"):
        return ("PASS", "Energy charges/plan line item found, with a nearby value.")
    return ("FAIL", "No energy charges/plan line item found (checked 'Energy Charges' and '... Energy Plan').")


def check_base_charge(text):
    """
    5.2 - Base Charge line item present.
    NOTE: a real Amigo commercial bill checked has NO separate Base
    Charge line at all (likely folded into the plan/energy charge line
    instead) - a FAIL here may be a genuine brand/account-type
    difference, not a missing-field error. Verify manually before
    treating this as a compliance gap.
    """
    if _label_then_nearby_value(text, r"(?i)base\s*charge", r"\$?\d"):
        return ("PASS", "Base Charge line item found, with a nearby value.")
    return ("FAIL", "No 'Base Charge' line item found - may be genuinely absent on this brand/account type rather than missing, verify manually.")


def check_tdu_delivery_charges(text):
    """5.3 - TDU/TDSP delivery (pass-through) charges present."""
    pattern = r"(?i)(tdsp|tdu)\s*delivery"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "TDU/TDSP delivery charges found, with a nearby value.")
    return ("FAIL", "No TDU/TDSP delivery charges line item found.")


def check_gross_receipts_tax(text):
    """5.4 - Gross receipts tax/reimbursement present."""
    pattern = r"(?i)gross\s*receipt"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "Gross receipts tax/reimbursement line item found.")
    return ("FAIL", "No gross receipts tax/reimbursement line item found.")


def check_puc_assessment(text):
    """5.5 - PUC assessment present."""
    pattern = r"(?i)puc\s*assessment"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "PUC assessment line item found, with a nearby value.")
    return ("FAIL", "No PUC assessment line item found.")


def check_market_securitization(text):
    """5.6 - Market securitization charge present."""
    pattern = r"(?i)market\s*securitization"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "Market securitization line item found, with a nearby value.")
    return ("FAIL", "No market securitization line item found - note this may be brand-specific, not all REPs itemize this separately.")


def check_total_current_charges(text):
    """
    5.1/5.8 combined - the overall 'Total Current Charges' or
    'Total Amount Due' rollup line is present (energy charges + all
    line items summed).
    """
    pattern = r"(?i)total\s*(current\s*charges|amount\s*due)"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "Total charges/amount due rollup line found.")
    return ("FAIL", "No 'Total Current Charges' or 'Total Amount Due' rollup line found.")


# ---------------------------------------------------------------------------
# SECTION 6 checks - Agreement Details / Product Info
# Built from real bill: "Agreement Details" heading, date-range + plan name
# line, "The average price you paid for electricity this month is X¢ per
# kWh." message, "You have a valid contract until MM/DD/YYYY" message.
# variable_rate check is a best-guess phrase, NOT confirmed against a real
# variable-rate bill yet (the one bill checked has a fixed-rate plan).
# ---------------------------------------------------------------------------

def check_agreement_section(text):
    """6.1 - 'Agreement Details' section heading present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    if re.search(r"(?i)agreement\s*details", text):
        return ("PASS", "Agreement Details section heading found.")
    return ("FAIL", "No 'Agreement Details' section heading found.")


def check_contract_dates(text):
    """6.3 - Contract start/end or bill-cycle date range near Agreement Details."""
    if _label_then_nearby_value(text, r"(?i)agreement\s*details", r"\d{1,2}/\d{1,2}/\d{2,4}\s*-\s*\d{1,2}/\d{1,2}/\d{2,4}"):
        return ("PASS", "A date range was found near the Agreement Details section.")
    return ("FAIL", "No date range found near Agreement Details - verify manually.")


def check_expiration_notice(text):
    """
    6.4 - Contract expiration notice present.
    Accepts both word orders seen across brands: Tara/Amigo say "valid
    contract until MM/DD/YYYY", Just Energy says "contract valid until
    MM/DD/YYYY" - same information, swapped word order.
    """
    pattern = r"(?i)(valid\s*contract\s*until|contract\s*valid\s*until)\s*\d{1,2}/\d{1,2}/\d{2,4}"
    if re.search(pattern, text):
        return ("PASS", "Contract expiration notice found.")
    return ("FAIL", "No contract expiration notice found (checked both 'valid contract until' and 'contract valid until' wordings).")


def check_average_price_message(text):
    """6.5 - Average price per kWh message present (text only, not the calculation)."""
    pattern = r"(?i)average\s*price\s*you\s*paid\s*for\s*electricity"
    if re.search(pattern, text):
        return ("PASS", "Average price message found. NOTE: this only confirms the message text is present, not that the printed cents/kWh value is mathematically correct.")
    return ("FAIL", "No average price per kWh message found.")


def check_variable_rate_message(text):
    """
    6.6 - Variable rate disclosure message. UNCONFIRMED wording - the one
    real bill checked has a fixed-rate plan and doesn't show this message,
    so this pattern is a best guess, not verified against a real example.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)variable\s*rate"
    if re.search(pattern, text):
        return ("PASS", "A 'variable rate' phrase was found - verify this matches the actual required disclosure wording.")
    return ("SKIP", "No 'variable rate' phrase found - UNCONFIRMED whether this bill is even a variable-rate plan; this check hasn't been validated against a real variable-rate bill yet.")


# ---------------------------------------------------------------------------
# SECTION 8 checks - Usage History
# Built from real bill: "Usage history (KWH)" chart heading, with month
# abbreviations (Apr, May, Jun...) printed as axis labels below the chart.
# ---------------------------------------------------------------------------

def check_usage_history_heading(text):
    """8.1 - 'Usage history (KWH)' chart heading present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    if re.search(r"(?i)usage\s*history", text):
        return ("PASS", "Usage history chart heading found.")
    return ("FAIL", "No 'Usage history' chart heading found.")


def check_usage_history_month_labels(text):
    """
    8.2/8.3 - Historical monthly values / graph month labels. Checks for
    at least several 3-letter month abbreviations near the usage history
    heading, as a proxy for the chart's axis labels having extracted as
    text (charts/images may not always extract this way - a real gap
    here could also just mean the chart is an embedded image with no
    text layer, which this check can't distinguish from a missing chart).
    """
    match = re.search(r"(?i)usage\s*history", text)
    if not match:
        return ("FAIL", "No 'Usage history' section found to check for month labels.")
    nearby = text[match.end(): match.end() + 400]
    months_found = re.findall(MONTH_ABBR, nearby)
    if len(months_found) >= 6:
        return ("PASS", f"Found {len(months_found)} month labels near the usage history chart.")
    return ("FAIL", f"Only found {len(months_found)} month labels near usage history (expected ~12) - verify manually, chart may be an image with no text layer.")


# ---------------------------------------------------------------------------
# SECTION 9 checks - Payment Coupon / Remittance Stub
# Built from real bill: "Please return this portion with your payment"
# divider text, a long numeric string under the remittance barcode area,
# and a "Do Not Pay - AutoPay" flag seen on the autopay sample checked.
# Barcode/QR presence is explicitly NOT checked - see note below.
# ---------------------------------------------------------------------------

def check_remittance_stub_present(text):
    """9.1 - Return-payment / remittance stub section present."""
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)please\s*return\s*this\s*portion\s*with\s*your\s*payment"
    if re.search(pattern, text):
        return ("PASS", "Remittance stub divider text found ('Please return this portion with your payment').")
    return ("FAIL", "No remittance stub divider text found - verify manually, wording may differ by brand.")


def check_stub_reference_number(text):
    """
    9.8 - Long reference/routing number on the stub (OCR line under the
    barcode). Real bill showed a 30+ digit string. This is a weak proxy -
    a false PASS is possible if an unrelated long digit string appears
    elsewhere on the page.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"\b\d{20,}\b"
    if re.search(pattern, text):
        return ("PASS", "A long reference/routing number (20+ digits) was found - likely the stub OCR line, but not position-verified.")
    return ("FAIL", "No long reference/routing number found on the stub.")


def check_barcode_or_qr_present(text):
    """
    9.7 - Barcode/QR code presence. NOT CHECKABLE via text extraction - a
    barcode/QR is an image, not text, so pdfplumber's text layer will
    never show it either way. This always returns SKIP rather than a
    false PASS or FAIL. Confirming this needs an image-based check
    (e.g. counting embedded images on the stub page), which is a
    different kind of check from everything else in this script.
    """
    return ("SKIP", "Barcode/QR presence cannot be checked via text extraction - needs an image-based check, not implemented here.")


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

    # Section 1
    results["solar"] = check_solar(text, account_type)
    results["refer_a_friend"] = check_refer_a_friend(text, account_type)
    results["power_to_choose"] = check_power_to_choose(text, account_type)
    results["critical_care"] = check_critical_care(text, bill_month)
    results["things_you_should_know"] = check_things_you_should_know(text)
    results["unauthorized_charges"] = check_unauthorized_charges_notice(text, None)
    results["puct_complaint_info"] = check_puct_complaint_info(text)
    results["tdu_contact"] = check_tdu_contact(text, territory)

    # Section 2
    results["account_number"] = check_account_number(text)
    results["service_address_esi_id"] = check_service_address_and_esi_id(text)
    results["customer_name_billing_address"] = check_customer_name_and_billing_address(text)

    # Section 3
    results["bill_number"] = check_bill_number(text)
    results["bill_date_field"] = check_bill_date_field(text)
    results["bill_period"] = check_bill_period(text)
    results["previous_balance"] = check_previous_balance(text)
    results["current_charges"] = check_current_charges(text)
    results["payments_adjustments"] = check_payments_adjustments(text)
    results["amount_due"] = check_amount_due(text)
    results["due_date_field"] = check_due_date_field(text)

    # Section 4
    results["meter_table"] = check_meter_table_present(text)
    results["actual_or_estimated"] = check_actual_or_estimated_read(text)
    results["usage_kwh"] = check_usage_kwh_value(text)

    # Section 5
    results["energy_charges"] = check_energy_charges(text)
    results["base_charge"] = check_base_charge(text)
    results["tdu_delivery_charges"] = check_tdu_delivery_charges(text)
    results["gross_receipts_tax"] = check_gross_receipts_tax(text)
    results["puc_assessment"] = check_puc_assessment(text)
    results["market_securitization"] = check_market_securitization(text)
    results["total_current_charges"] = check_total_current_charges(text)

    # Section 6
    results["agreement_section"] = check_agreement_section(text)
    results["contract_dates"] = check_contract_dates(text)
    results["expiration_notice"] = check_expiration_notice(text)
    results["average_price_message"] = check_average_price_message(text)
    results["variable_rate_message"] = check_variable_rate_message(text)

    # Section 8
    results["usage_history_heading"] = check_usage_history_heading(text)
    results["usage_history_months"] = check_usage_history_month_labels(text)

    # Section 9
    results["remittance_stub"] = check_remittance_stub_present(text)
    results["stub_reference_number"] = check_stub_reference_number(text)
    results["barcode_qr"] = check_barcode_or_qr_present(text)

    return results


PRINT_ORDER = [
    # Section 1
    "solar", "refer_a_friend", "power_to_choose", "critical_care",
    "things_you_should_know", "unauthorized_charges", "puct_complaint_info", "tdu_contact",
    # Section 2
    "account_number", "service_address_esi_id", "customer_name_billing_address",
    # Section 3
    "bill_number", "bill_date_field", "bill_period", "previous_balance",
    "current_charges", "payments_adjustments", "amount_due", "due_date_field",
    # Section 4
    "meter_table", "actual_or_estimated", "usage_kwh",
    # Section 5
    "energy_charges", "base_charge", "tdu_delivery_charges", "gross_receipts_tax",
    "puc_assessment", "market_securitization", "total_current_charges",
    # Section 6
    "agreement_section", "contract_dates", "expiration_notice",
    "average_price_message", "variable_rate_message",
    # Section 8
    "usage_history_heading", "usage_history_months",
    # Section 9
    "remittance_stub", "stub_reference_number", "barcode_qr",
]


def print_result(results):
    print(f"\n{results['file']}")
    print(f"  Account type: {results['account_type']} | Territory: {results['territory']} | Bill month: {results['bill_month']}")
    for rule in PRINT_ORDER:
        status, detail = results[rule]
        marker = {"PASS": "[PASS]", "FAIL": "[FAIL]", "SKIP": "[SKIP]", "REVIEW": "[REVIEW]"}[status]
        print(f"  {marker} {rule:26} {detail}")


# Plain-English column headers for the Excel export - non-technical readers
# (Abby, Sif) shouldn't have to know what "esi_id" or "tdu_contact" means.
RULE_LABELS = {
    "solar": "Solar Message",
    "refer_a_friend": "Refer a Friend Message",
    "power_to_choose": "Power to Choose Message",
    "critical_care": "Critical Care Message",
    "things_you_should_know": "Things You Should Know Notice",
    "unauthorized_charges": "Unauthorized Charges Notice",
    "puct_complaint_info": "PUCT Complaint Info",
    "tdu_contact": "TDU Emergency Contact",
    "account_number": "Account Number",
    "service_address_esi_id": "Service Address / ESI ID",
    "customer_name_billing_address": "Customer Name / Billing Address",
    "bill_number": "Bill Number",
    "bill_date_field": "Bill Date",
    "bill_period": "Bill Period",
    "previous_balance": "Previous Balance",
    "current_charges": "Current Charges",
    "payments_adjustments": "Payments / Adjustments",
    "amount_due": "Amount Due",
    "due_date_field": "Due Date",
    "meter_table": "Meter Reading Table",
    "actual_or_estimated": "Actual / Estimated Read",
    "usage_kwh": "Usage (kWh)",
    "energy_charges": "Energy Charges",
    "base_charge": "Base Charge",
    "tdu_delivery_charges": "TDU Delivery Charges",
    "gross_receipts_tax": "Gross Receipts Tax",
    "puc_assessment": "PUC Assessment",
    "market_securitization": "Market Securitization",
    "total_current_charges": "Total Current Charges",
    "agreement_section": "Agreement Details Section",
    "contract_dates": "Contract Dates",
    "expiration_notice": "Contract Expiration Notice",
    "average_price_message": "Average Price Message",
    "variable_rate_message": "Variable Rate Message",
    "usage_history_heading": "Usage History Heading",
    "usage_history_months": "Usage History Month Labels",
    "remittance_stub": "Remittance Stub",
    "stub_reference_number": "Stub Reference Number",
    "barcode_qr": "Barcode / QR Code",
}

STATUS_FILL = {
    "PASS": PatternFill(start_color="C6EFCE", end_color="C6EFCE", fill_type="solid"),   # green
    "FAIL": PatternFill(start_color="FFC7CE", end_color="FFC7CE", fill_type="solid"),   # red
    "REVIEW": PatternFill(start_color="FFEB9C", end_color="FFEB9C", fill_type="solid"), # yellow
    "SKIP": PatternFill(start_color="D9D9D9", end_color="D9D9D9", fill_type="solid"),   # gray
}
STATUS_FONT = {
    "PASS": Font(name="Arial", color="006100"),
    "FAIL": Font(name="Arial", color="9C0006"),
    "REVIEW": Font(name="Arial", color="9C6500"),
    "SKIP": Font(name="Arial", color="595959"),
}


def write_excel_report(all_results, output_path):
    """
    Writes a plain-English Excel report of every bill's check results -
    for Abby, Sif, or anyone who needs to review results without running
    Python or reading a terminal. Same precedent as the Missed AWT
    Interval Report built for WFM: a spreadsheet Abby can open and filter
    herself, not a script someone has to run for her.

    Sheet 1 "Results" - one row per bill, one column per check, colored
    PASS/FAIL/REVIEW/SKIP with the plain-English reason in the cell,
    autofilter enabled on the header row so she can filter to FAILs.

    Sheet 2 "Summary" - one row per check, counting how many bills
    passed/failed/etc, sorted so the most-failing checks are easy to spot
    without scrolling the raw data.
    """
    wb = Workbook()

    # ---------------- Sheet 1: Results ----------------
    ws = wb.active
    ws.title = "Results"

    header_font = Font(name="Arial", bold=True, color="FFFFFF")
    header_fill = PatternFill(start_color="004061", end_color="004061", fill_type="solid")

    headers = ["File", "Account Type", "Territory", "Bill Month", "Bill Year"] + [RULE_LABELS[r] for r in PRINT_ORDER]
    for col_idx, header in enumerate(headers, start=1):
        cell = ws.cell(row=1, column=col_idx, value=header)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(wrap_text=True, vertical="center")

    for row_idx, results in enumerate(all_results, start=2):
        ws.cell(row=row_idx, column=1, value=results["file"]).font = Font(name="Arial")
        ws.cell(row=row_idx, column=2, value=results["account_type"]).font = Font(name="Arial")
        ws.cell(row=row_idx, column=3, value=results["territory"]).font = Font(name="Arial")
        ws.cell(row=row_idx, column=4, value=results["bill_month"]).font = Font(name="Arial")
        ws.cell(row=row_idx, column=5, value=results["bill_year"]).font = Font(name="Arial")

        for col_offset, rule in enumerate(PRINT_ORDER):
            status, detail = results[rule]
            cell = ws.cell(row=row_idx, column=6 + col_offset, value=f"{status}: {detail}")
            cell.fill = STATUS_FILL[status]
            cell.font = STATUS_FONT[status]
            cell.alignment = Alignment(wrap_text=True, vertical="top")

    ws.freeze_panes = "F2"  # freeze header row + the 5 identifying columns
    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}{len(all_results) + 1}"
    ws.column_dimensions["A"].width = 45
    for col_idx in range(2, 6):
        ws.column_dimensions[get_column_letter(col_idx)].width = 14
    for col_idx in range(6, len(headers) + 1):
        ws.column_dimensions[get_column_letter(col_idx)].width = 32
    ws.row_dimensions[1].height = 45

    # ---------------- Sheet 2: Summary ----------------
    ws2 = wb.create_sheet("Summary")
    ws2.cell(row=1, column=1, value="Bill PDF Audit - Summary").font = Font(name="Arial", bold=True, size=14)
    ws2.cell(row=2, column=1, value=f"Total bills checked: {len(all_results)}").font = Font(name="Arial")

    summary_headers = ["Check", "Passed", "Failed", "Needs Review", "Skipped"]
    for col_idx, header in enumerate(summary_headers, start=1):
        cell = ws2.cell(row=4, column=col_idx, value=header)
        cell.font = header_font
        cell.fill = header_fill

    counts = []
    for rule in PRINT_ORDER:
        passed = sum(1 for r in all_results if r[rule][0] == "PASS")
        failed = sum(1 for r in all_results if r[rule][0] == "FAIL")
        review = sum(1 for r in all_results if r[rule][0] == "REVIEW")
        skipped = sum(1 for r in all_results if r[rule][0] == "SKIP")
        counts.append((RULE_LABELS[rule], passed, failed, review, skipped))

    # Sort so the checks with the most failures show up first - the ones
    # most worth Abby's attention, not buried alphabetically.
    counts.sort(key=lambda row: row[2], reverse=True)

    for row_idx, (label, passed, failed, review, skipped) in enumerate(counts, start=5):
        ws2.cell(row=row_idx, column=1, value=label).font = Font(name="Arial")
        fail_cell = ws2.cell(row=row_idx, column=3, value=failed)
        fail_cell.font = Font(name="Arial", bold=(failed > 0), color="9C0006" if failed > 0 else "000000")
        ws2.cell(row=row_idx, column=2, value=passed).font = Font(name="Arial")
        ws2.cell(row=row_idx, column=4, value=review).font = Font(name="Arial")
        ws2.cell(row=row_idx, column=5, value=skipped).font = Font(name="Arial")

    ws2.column_dimensions["A"].width = 34
    for col in ["B", "C", "D", "E"]:
        ws2.column_dimensions[col].width = 14

    # ---------------- Sheet 3: PowerBI Data (long format) ----------------
    # Power BI (and most BI tools) work far better with "long" data - one
    # row per bill PER CHECK, with Status and Detail as separate clean
    # columns - than with the wide "Results" sheet above, where each cell
    # mixes status and reason together as one text string. This sheet is
    # what should actually get connected in Power BI; Results/Summary are
    # for opening directly in Excel.
    ws3 = wb.create_sheet("PowerBI_Data")
    pbi_headers = ["File", "Account Type", "Territory", "Bill Month", "Bill Year", "Check", "Status", "Detail"]
    for col_idx, header in enumerate(pbi_headers, start=1):
        cell = ws3.cell(row=1, column=col_idx, value=header)
        cell.font = header_font
        cell.fill = header_fill

    row_idx = 2
    for results in all_results:
        for rule in PRINT_ORDER:
            status, detail = results[rule]
            ws3.cell(row=row_idx, column=1, value=results["file"]).font = Font(name="Arial")
            ws3.cell(row=row_idx, column=2, value=results["account_type"]).font = Font(name="Arial")
            ws3.cell(row=row_idx, column=3, value=results["territory"]).font = Font(name="Arial")
            ws3.cell(row=row_idx, column=4, value=results["bill_month"]).font = Font(name="Arial")
            ws3.cell(row=row_idx, column=5, value=results["bill_year"]).font = Font(name="Arial")
            ws3.cell(row=row_idx, column=6, value=RULE_LABELS[rule]).font = Font(name="Arial")
            status_cell = ws3.cell(row=row_idx, column=7, value=status)
            status_cell.font = STATUS_FONT[status]
            status_cell.fill = STATUS_FILL[status]
            ws3.cell(row=row_idx, column=8, value=detail).font = Font(name="Arial")
            row_idx += 1

    ws3.auto_filter.ref = f"A1:{get_column_letter(len(pbi_headers))}{row_idx - 1}"
    ws3.freeze_panes = "A2"
    ws3.column_dimensions["A"].width = 45
    for col in ["B", "C", "D", "E", "G"]:
        ws3.column_dimensions[col].width = 14
    ws3.column_dimensions["F"].width = 32
    ws3.column_dimensions["H"].width = 50

    wb.save(output_path)
    print(f"\nExcel report written to: {output_path}")


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


def run_batch(folder, manifest_path=None, excel_path=None):
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
        if results is None:
            print(f"\n{fname}  -- SKIPPED (check_bill returned no results, likely a PDF text-extraction issue)")
            continue

        print_result(results)
        all_results.append(results)

    # Summary - counts FAILs across the full check list, not just Section 1
    total = len(all_results)
    fails = [
        (r["file"], rule)
        for r in all_results
        for rule in PRINT_ORDER
        if r[rule][0] == "FAIL"
    ]
    print(f"\n{'='*60}")
    print(f"SUMMARY: {total} bills checked, {len(fails)} rule failures found")
    print(f"{'='*60}")

    if excel_path and all_results:
        write_excel_report(all_results, excel_path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Bill PDF Audit Tool - Phase 1 rule checker")
    parser.add_argument("pdf", nargs="?", help="Path to a single PDF to check")
    parser.add_argument("--account-type", choices=["residential", "commercial"], help="Account type for single-file mode")
    parser.add_argument("--territory", help="Utility territory for single-file mode (Centerpoint/Oncor/AEP/TNMP/Lubbock)")
    parser.add_argument("--batch", help="Folder to batch-check (recursively finds all PDFs)")
    parser.add_argument("--manifest", help="Optional CSV with columns: filename,account_type,territory")
    parser.add_argument("--excel", help="Optional path to write an Excel report (e.g. bill_audit_report.xlsx) - for non-technical review (Abby, Sif), same pattern as the Missed AWT Interval Report")
    args = parser.parse_args()

    if args.batch:
        run_batch(args.batch, args.manifest, args.excel)
    elif args.pdf:
        if not args.account_type or not args.territory:
            print("Single-file mode requires --account-type and --territory")
            sys.exit(1)
        results = check_bill(args.pdf, args.account_type, args.territory)
        print_result(results)
        if args.excel:
            write_excel_report([results], args.excel)
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
#
# WHAT STILL NEEDS DOING (honest status, Aug 2026):
#   - Section 7 (Messages & Regulatory Notices) is Section 1 above - already
#     done, just numbered differently between this script and the original
#     9-section checklist from Abby's document.
#   - Section 10 (PDF Display & Formatting) is NOT in this script at all -
#     see the module docstring at the top for why.
#   - Sections 4, 5, 6, 8, 9 are built from ONE real bill (Tara, TNMP).
#     Spot-check at least one Amigo and one Just Energy sample before
#     trusting these results at full batch scale - Sections 2 and 3 both
#     needed real fixes after this same step, so assume these will too.
#   - The average-price-per-kWh CALCULATION (not just message presence)
#     is not implemented - would need numeric extraction and a real
#     formula check, a different task from presence-only checking.
# ---------------------------------------------------------------------------


Create a summary page with: a card showing total unique bills checked, a donut chart showing the breakdown of Status (PASS/FAIL/REVIEW/SKIP), a bar chart showing failure count by Check sorted highest to lowest, and a table showing Status by Territory.”