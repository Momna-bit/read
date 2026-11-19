
py check_bill_rules_WITH_EXCEL.py --easy "Bills to check"



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
# "NOT APPLICABLE" LIST  (edit this list when Abby/Jonathon confirm more cases)
#
# Some brands never print certain lines (for example, Amigo and Tara do not
# show a separate Base Charge line). For those brand + account-type
# combinations, a missing line is reported as N/A instead of FAIL.
# IMPORTANT: if the line IS found on the bill, the result is still PASS.
# A brand that is not listed here still gets a normal FAIL when a line is
# missing, so nothing real is hidden.
#
# Brand keys:  "amigo", "tara", "just"   Account types: "residential", "commercial"
# Starting list is based on the 6 sample bills tested in Nov 2026 -
# please have Abby confirm it.
# ---------------------------------------------------------------------------
NOT_APPLICABLE_RULES = {
    "base_charge": {
        ("amigo", "residential"), ("amigo", "commercial"),
        ("tara", "residential"), ("tara", "commercial"),
    },
    "market_securitization": {
        ("just", "residential"),
        ("tara", "commercial"),
    },
}

BRAND_NAMES = {"amigo": "Amigo", "tara": "Tara", "just": "Just Energy"}

# ---------------------------------------------------------------------------
# CUSTOMER NAME CHECK SETTINGS  (change these if the limits turn out wrong)
# ---------------------------------------------------------------------------
NAME_MAX_WORD_LENGTH = 20          # one word (e.g. a first name) longer than this is flagged
NAME_MAX_LENGTH_RESIDENTIAL = 35   # whole name longer than this is flagged (people)
NAME_MAX_LENGTH_COMMERCIAL = 50    # whole name longer than this is flagged (businesses)
NAME_PLACEHOLDER_WORDS = r"(test|testing|tester|dummy|sample|unknown|null|n/?a)"
NAME_KEYBOARD_MASH = ["asdf", "qwer", "zxcv", "hjkl", "wasd", "uiop"]  # 3-letter runs removed: real names contain them (e.g. QAZI)


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


def find_bill_period_end_month(text):
    """
    Backup for when the Bill Date is missing. Looks for
    'Bill Period - MM/DD/YY thru MM/DD/YY' and returns the month the
    period ENDS in, as an int, or None if not found. The bill date is
    normally a couple of days after the period ends, so this is a good
    estimate, but not exact near the end of a month.
    """
    match = re.search(
        r"Bill Period\s*[-:]?\s*\d{1,2}/\d{1,2}/\d{2,4}\s*(?:thru|through|to|-)\s*(\d{1,2})/\d{1,2}/\d{2,4}",
        text, re.IGNORECASE)
    if not match:
        return None
    month = int(match.group(1))
    return month if 1 <= month <= 12 else None


def normalize_territory(territory):
    t = territory.strip().lower()
    if "center" in t:
        return "centerpoint"
    if "oncor" in t:
        return "oncor"
    if "aep" in t:
        return "aep"
    if "tnmp" in t or "new mexico" in t:
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


def detect_brand(text):
    """
    Works out which brand printed the bill by counting brand names in the
    bill text. Returns "amigo", "tara", "just", or None if it can't tell.
    """
    lower = (text or "").lower()
    counts = {
        "amigo": lower.count("amigo energy") + lower.count("amigoenergy"),
        "tara": lower.count("tara energy") + lower.count("taraenergy"),
        "just": lower.count("just energy") + lower.count("justenergy"),
    }
    best = max(counts, key=counts.get)
    return best if counts[best] > 0 else None


def _not_applicable(check_name, brand, account_type, line_name):
    """Returns an N/A result if this brand + account type is on the N/A list, else None."""
    if brand and (brand, account_type) in NOT_APPLICABLE_RULES.get(check_name, set()):
        return ("N/A", f"Not applicable - {BRAND_NAMES[brand]} {account_type} bills do not print a separate {line_name} line.")
    return None


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


def check_critical_care(text, bill_month, estimated_month=None):
    """
    bill_month: month from the Bill Date (exact), or None if the Bill Date is missing.
    estimated_month: backup month from the end of the Bill Period, used only
    when the Bill Date is missing. A FAIL based on an estimate is shown as
    REVIEW instead, because the estimate can be off near a month end.
    """
    present = CRITICAL_CARE_PHRASE in text.lower()
    if bill_month is None and estimated_month is None:
        return ("SKIP", "Not checked: no Bill Date and no Bill Period found, so the month is unknown. Fix the Bill Date first.")
    if bill_month is None:
        month = estimated_month
        required = month in CRITICAL_CARE_REQUIRED_MONTHS
        note = f"Bill Date is missing, so month {month} was estimated from the Bill Period"
        if required and present:
            return ("PASS", f"Critical Care message present in required month ({note})")
        if required and not present:
            return ("REVIEW", f"Critical Care message not found; month {month} requires it ({note}) - confirm the real bill month")
        if not required and present:
            return ("REVIEW", f"Critical Care message present in month {month}, which should not have it ({note}) - confirm the real bill month")
        return ("PASS", f"Critical Care correctly absent outside April/October ({note})")
    required = bill_month in CRITICAL_CARE_REQUIRED_MONTHS
    if required and present:
        return ("PASS", f"Critical Care message present in required month ({bill_month})")
    if required and not present:
        return ("FAIL", f"Critical Care message MISSING in required month ({bill_month})")
    if not required and present:
        return ("FAIL", f"Critical Care message present in month {bill_month} - should ONLY appear in April/October")
    return ("PASS", f"Critical Care correctly absent outside April/October (month {bill_month})")


def check_things_you_should_know(text):
    # Strip ALL whitespace before comparing, so letter-spaced headers
    # (e.g. "T H I N G S  Y O U...") still match correctly.
    squeezed = re.sub(r"\s+", "", text.upper())
    if "THINGSYOUSHOULDKNOWABOUTYOURBILL" in squeezed:
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


def find_emergency_number_on_bill(text):
    """Return the phone number printed next to the outage / emergency line, or None."""
    if not text:
        return None
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if re.search(r"(?i)outages?\s*/\s*emergenc|emergenc\w*\s+and\s+power\s+outage|emergenc\w*\s*(call|number)", line):
            context = " ".join(lines[max(0, i - 1):i + 3])
            m = re.search(r"\(?\d{3}\)?[-. ]\d{3}[-. ]\d{4}", context)
            if m:
                return m.group(0)
    return None


def check_tdu_contact(text, territory):
    norm = normalize_territory(territory)
    on_bill = find_emergency_number_on_bill(text)
    shown = f"Number printed on the bill: {on_bill}." if on_bill else "No emergency number found on the bill."
    if norm == "lubbock":
        return ("SKIP", f"No reference number on file yet for Lubbock. {shown} Needs confirming.")
    expected = TDU_CONTACT_DIGITS.get(norm)
    if not expected:
        return ("SKIP", f"Power company not clear ('{territory}'), so no reference number. {shown} Needs confirming.")
    text_digits = digits_only(text)
    if expected in text_digits:
        return ("PASS", f"Correct {territory} emergency number found. {shown}")
    return ("FAIL", f"Expected {territory} emergency number not found on bill. {shown}")


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
    """
    2.3 / 2.5 combined - 'Service at Premise #' label + ESI-ID-format value.
    CONFIRMED against all 31 real bills (Aug 2026): the premise ID length
    genuinely varies by territory, all starting with "10":
      - AEP / Oncor / TNMP: 17 digits total (10 + 15 more)
      - CenterPoint:         22 digits total (10 + 20 more)
      - Lubbock:             15 digits total (10 + 13 more)
    Originally only the 17-digit AEP/Oncor/TNMP format was recognized,
    which produced false FAILs on every real CenterPoint and Lubbock bill
    even though the label and a valid-looking ID were both present.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    esiid_format = r"\b10(\d{13}|\d{15}|\d{20})\b"
    label_pattern = r"(?i)service\s*(address|at\s*premise)\s*#?\s*[:\-]?"
    has_label = re.search(label_pattern, text)
    has_esiid = re.search(esiid_format, text)
    if has_label and has_esiid:
        return ("PASS", "Service premise field found, with a value matching a confirmed real ESI ID format (15, 17, or 22 digits depending on territory).")
    if has_esiid and not has_label:
        return ("PASS", "An ESI-ID-format number was found, though not under a recognized label - verify manually.")
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


def extract_customer_name(text):
    """
    Finds the customer name printed at the top of the bill. On every bill
    layout checked (Amigo, Tara, Just Energy; residential and commercial)
    the name sits on the same line as, and just before, "Service at Premise #".
    Returns the name text (may be empty), or None if that line isn't found.
    """
    for line in (text or "")[:900].split("\n"):
        m = re.search(r"(?i)^(.*?)\s*service\s*(?:at\s*premise|address)", line)
        if m:
            return re.sub(r"\s+", " ", m.group(1)).strip()
    return None


def check_customer_name_looks_valid(text, account_type):
    """
    Flags bills where the customer name looks wrong (requested by Jonathon,
    Nov 2026). Clear problems are FAIL; suspicious-looking ones are REVIEW,
    because a person should glance at the real bill.
      FAIL   - name is blank, or contains a placeholder word like "test"
      REVIEW - looks like random letters, a word or the whole name is too
               long, or it has odd symbols/numbers
    The customer's actual name is deliberately NOT written into the report.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    name = extract_customer_name(text)
    if name is None:
        return ("SKIP", "Could not find the line with the customer name - check manually.")

    words = re.findall(r"[A-Za-z]+", name)
    if not words:
        return ("FAIL", "Customer name is blank (or has no letters).")
    # Placeholder words. Compared against whole words only ("NA'QUIN" is not
    # "NA"). A placeholder as the first word, or the only words, is a FAIL.
    # A placeholder later in the name is only REVIEW, because it can be a
    # real surname (for example "Sample").
    placeholder_set = {"test", "testing", "tester", "dummy", "sample", "unknown", "null", "na", "n/a"}
    name_tokens = [re.sub(r"[^a-z/]", "", t.lower()) for t in name.split()]
    flags = [t in placeholder_set for t in name_tokens]
    if flags and (flags[0] or all(flags)):
        return ("FAIL", "Customer name contains a placeholder word (such as 'test' or 'sample').")

    commercial = (account_type == "commercial")
    problems = []
    if any(flags):
        problems.append("a word looks like a placeholder (such as 'test' or 'sample'), but it could be a real surname")

    # Too long
    tokens = name.split()
    longest = max(len(t) for t in tokens)
    max_total = NAME_MAX_LENGTH_COMMERCIAL if commercial else NAME_MAX_LENGTH_RESIDENTIAL
    if longest > NAME_MAX_WORD_LENGTH:
        problems.append(f"one word is {longest} characters long (limit {NAME_MAX_WORD_LENGTH})")
    if len(name) > max_total:
        problems.append(f"the name is {len(name)} characters long (limit {max_total})")

    # Looks like random letters
    for w in words:
        lw = w.lower()
        if len(w) >= 5 and not re.search(r"[aeiouy]", lw):
            problems.append("a word has no vowels (looks like random letters)")
            break
        if len(w) == 4 and not commercial and not re.search(r"[aeiouy]", lw):
            problems.append("a word has no vowels (looks like random letters)")
            break
        if re.search(r"[^aeiouy\W\d_]{6,}", lw):
            problems.append("a word has 6 or more consonants in a row (looks like random letters)")
            break
    if re.search(r"(.)\1{3,}", name.lower()):
        problems.append("the same character repeats 4 or more times")
    if any(k in name.lower().replace(" ", "") for k in NAME_KEYBOARD_MASH):
        problems.append("looks like keyboard mashing")
    if all(len(w) == 1 for w in words):
        problems.append("the name is only single letters")

    # Odd symbols or numbers
    allowed = r"^[A-Za-z0-9 .,'\-&#/()@+:]+$" if commercial else r"^[A-Za-z .,'\-&/]+$"
    if not re.match(allowed, name):
        problems.append("it has numbers or symbols that are unusual in a name" if not commercial else "it has unusual symbols")

    if problems:
        return ("REVIEW", "Customer name looks unusual: " + "; ".join(problems) + ". Manual check needed.")
    return ("PASS", "Customer name looks normal (not blank, no placeholder words, no sign of random letters, normal length).")


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
    CONFIRMED (Aug 2026): at least one real Tara commercial bill is a
    fixed-load account with no meter at all, using "UNMETERED" as a third,
    legitimate read-type value instead of ACT/EST - added as a recognized
    value, since this is a real category, not a wording bug.
    """
    if not text:
        return ("FAIL", "No text extracted from this PDF.")
    pattern = r"(?i)\b(ACT|EST|Actual|Estimated|Unmetered)\b"
    if re.search(pattern, text):
        return ("PASS", "Actual/Estimated/Unmetered read indicator found.")
    return ("FAIL", "No Actual/Estimated/Unmetered read indicator found (checked 'ACT', 'EST', 'Actual', 'Estimated', 'Unmetered').")


def check_usage_kwh_value(text):
    """
    4.6 - Usage (kWh) value present, near a 'Usage' label.
    CONFIRMED (Aug 2026): Just Energy's meter table has two extra columns
    (kW Demand, Power Factor) not present on Tara/Amigo bills, which pushes
    the real usage value past the default 150-character search window -
    up to 171 characters were needed on real JE bills. Widened to 200 for
    safe margin; the matching pattern itself is unchanged.
    """
    if _label_then_nearby_value(text, r"(?i)usage", r"[\d,]+\.\d{2}", window=200):
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

def check_energy_charge(text):
    """
    5.1 - Energy charge/rate/amount line item present. Brands label this
    differently: Tara/Amigo call it '[Plan Name] Energy Plan', Just
    Energy calls it 'Energy Charge' explicitly, and Tara residential bills
    fold the energy charge into a per-kWh line labeled "RKWH" / "Residential
    KWH" instead of a separate line - CONFIRMED against real Tara
    residential bills (Aug 2026), e.g. "RKWH : Residential KWH
    ...2,984.00 0.09200 $274.53". Checking for any of these confirmed
    real wordings.
    """
    pattern = r"(?i)(energy\s*(charge|plan)|r\s*kwh|residential\s*kwh)"
    if _label_then_nearby_value(text, pattern, r"\$?-?\d"):
        return ("PASS", "Energy charge line item found, with a nearby value (checked 'Energy Charge', '...Energy Plan', and 'RKWH'/'Residential KWH').")
    return ("FAIL", "No energy charge line item found (checked 'Energy Charge', '...Energy Plan', and 'RKWH'/'Residential KWH').")


def check_base_charge(text, brand=None, account_type=None):
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
    na = _not_applicable("base_charge", brand, account_type, "Base Charge")
    if na:
        return na
    return ("FAIL", "No 'Base Charge' line item found - may be genuinely absent on this brand/account type rather than missing, verify manually.")


def check_tdu_delivery_charges(text):
    """
    5.3 - TDU/TDSP delivery (pass-through) charges present.
    CONFIRMED (Aug 2026): at least one real Just Energy bill labels this
    line "TDU Pass-Through Charges" instead of "...Delivery" - added as a
    recognized wording alongside the existing "Delivery" match. Note: two
    other real JE bills (a "Nights Free Energy Credit" plan) have no
    separate delivery/pass-through line at all - that appears to be a
    genuine plan-specific bundling, not a wording issue, and is left as a
    real FAIL for manual review.
    """
    pattern = r"(?i)(tdsp|tdu)\s*(delivery|pass[\s\-]*through)"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "TDU/TDSP delivery or pass-through charges found, with a nearby value.")
    return ("FAIL", "No TDU/TDSP delivery or pass-through charges line item found.")


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


def check_market_securitization(text, brand=None, account_type=None):
    """5.6 - Market securitization charge present."""
    pattern = r"(?i)market\s*securitization"
    if _label_then_nearby_value(text, pattern, r"\$?\d"):
        return ("PASS", "Market securitization line item found, with a nearby value.")
    na = _not_applicable("market_securitization", brand, account_type, "Market Securitization")
    if na:
        return na
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

    CONFIRMED (Aug 2026), two real, separate false-failure causes fixed:
    1. The chart's 2-digit year sub-labels get interleaved character-by-
       character with the month abbreviations during text extraction on
       several real bills, e.g. "Apr" extracts as "A 25 pr" instead of
       "Apr 25". Digits and whitespace are now stripped from the search
       window before matching, the same squeeze approach already used for
       the "Things You Should Know" notice, so "A 25 pr" correctly reduces
       to "Apr".
    2. Some brands interleave more regulatory text (average price message,
       contract date, Critical Care notice) between the heading and the
       actual axis labels than others, pushing real labels past the
       original 400-character window - widened to 600 for safe margin.
    """
    match = re.search(r"(?i)usage\s*history", text)
    if not match:
        return ("FAIL", "No 'Usage history' section found to check for month labels.")
    nearby = text[match.end(): match.end() + 600]
    squeezed = re.sub(r"[\d\s]", "", nearby)
    months_found = re.findall(MONTH_ABBR, squeezed, flags=re.IGNORECASE)
    if len(months_found) >= 6:
        return ("PASS", f"Found {len(months_found)} month labels near the usage history chart.")
    if len(months_found) == 0:
        return ("FAIL", "No month labels found near the usage history chart - the chart may be missing or an image with no text layer.")
    return ("REVIEW", f"Only found {len(months_found)} month labels near usage history (expected ~12) - likely a newer account with less history; check the bill if unsure.")


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

def check_bill(pdf_path, account_type, territory, text=None):
    """
    account_type: 'residential' or 'commercial'
    territory: one of Centerpoint / Oncor / AEP / TNMP / Lubbock
    """
    account_type = account_type.strip().lower()
    if text is None:
        text = extract_text(pdf_path)
    bill_month, bill_year = find_bill_date(text)
    brand = detect_brand(text)

    results = {
        "file": os.path.basename(pdf_path),
        "account_type": account_type,
        "territory": territory,
        "bill_month": bill_month,
        "bill_year": bill_year,
    }

    if SKIP_SPANISH and any(m in text for m in SPANISH_MARKERS):
        for rule in PRINT_ORDER:
            results[rule] = ("SKIP", "Spanish bill - not checked yet (the tool only knows the English wording).")
        return results

    # Section 1
    results["solar"] = check_solar(text, account_type)
    results["refer_a_friend"] = check_refer_a_friend(text, account_type)
    results["power_to_choose"] = check_power_to_choose(text, account_type)
    estimated_month = find_bill_period_end_month(text) if bill_month is None else None
    results["critical_care"] = check_critical_care(text, bill_month, estimated_month)
    results["things_you_should_know"] = check_things_you_should_know(text)
    results["unauthorized_charges"] = check_unauthorized_charges_notice(text, None)
    results["puct_complaint_info"] = check_puct_complaint_info(text)
    results["tdu_contact"] = check_tdu_contact(text, territory)

    # Section 2
    results["account_number"] = check_account_number(text)
    results["service_address_esi_id"] = check_service_address_and_esi_id(text)
    results["customer_name_billing_address"] = check_customer_name_and_billing_address(text)
    results["customer_name_looks_valid"] = check_customer_name_looks_valid(text, account_type)

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
    results["energy_charge"] = check_energy_charge(text)
    results["base_charge"] = check_base_charge(text, brand, account_type)
    results["tdu_delivery_charges"] = check_tdu_delivery_charges(text)
    results["gross_receipts_tax"] = check_gross_receipts_tax(text)
    results["puc_assessment"] = check_puc_assessment(text)
    results["market_securitization"] = check_market_securitization(text, brand, account_type)
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


# Set by the --english-only flag. Spanish bills are marked SKIP, not checked.
SKIP_SPANISH = False
SPANISH_MARKERS = ("Cuenta #", "Fecha del Recibo", "Servicio a la Locaci")


PRINT_ORDER = [
    # Section 1
    "solar", "refer_a_friend", "power_to_choose", "critical_care",
    "things_you_should_know", "unauthorized_charges", "puct_complaint_info", "tdu_contact",
    # Section 2
    "account_number", "service_address_esi_id", "customer_name_billing_address",
    "customer_name_looks_valid",
    # Section 3
    "bill_number", "bill_date_field", "bill_period", "previous_balance",
    "current_charges", "payments_adjustments", "amount_due", "due_date_field",
    # Section 4
    "meter_table", "actual_or_estimated", "usage_kwh",
    # Section 5
    "energy_charge", "base_charge", "tdu_delivery_charges", "gross_receipts_tax",
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
        marker = {"PASS": "[PASS]", "FAIL": "[FAIL]", "SKIP": "[SKIP]", "REVIEW": "[REVIEW]", "N/A": "[N/A]"}[status]
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
    "customer_name_looks_valid": "Customer Name Looks Valid",
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
    "energy_charge": "Energy Charge",
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
    "N/A": PatternFill(start_color="DDEBF7", end_color="DDEBF7", fill_type="solid"),    # light blue
}
STATUS_FONT = {
    "PASS": Font(name="Arial", color="006100"),
    "FAIL": Font(name="Arial", color="9C0006"),
    "REVIEW": Font(name="Arial", color="9C6500"),
    "SKIP": Font(name="Arial", color="595959"),
    "N/A": Font(name="Arial", color="1F4E78"),
}


def write_excel_report(all_results, output_path):
    wb = Workbook()

    ws0 = wb.active
    ws0.title = "How to Use This Report"

    def guide_heading(row, text):
        cell = ws0.cell(row=row, column=1, value=text)
        cell.font = Font(name="Arial", bold=True, size=14, color="004061")

    def guide_text(row, text):
        cell = ws0.cell(row=row, column=1, value=text)
        cell.font = Font(name="Arial", size=11)
        cell.alignment = Alignment(wrap_text=False, vertical="top")

    def guide_status_row(row, status, meaning):
        status_cell = ws0.cell(row=row, column=1, value=status)
        status_cell.font = STATUS_FONT[status]
        status_cell.fill = STATUS_FILL[status]
        status_cell.alignment = Alignment(horizontal="center", vertical="center")
        meaning_cell = ws0.cell(row=row, column=2, value=meaning)
        meaning_cell.font = Font(name="Arial", size=11)
        meaning_cell.alignment = Alignment(wrap_text=True, vertical="center")

    guide_heading(1, "Bill PDF Audit — How to Use This Report")
    guide_text(2, "Here's the short version: we took real electricity bills and checked each one against the list of things Texas requires to be on there. Every row in the \"Results\" tab is one bill. Every column is one required item — was it actually on the bill or not. This page walks you through how to read what we found.")

    guide_heading(4, "What the five colors mean")
    ws0.cell(row=5, column=1, value="Status").font = Font(name="Arial", bold=True)
    ws0.cell(row=5, column=2, value="What it means").font = Font(name="Arial", bold=True)
    guide_status_row(6, "PASS", "We found this required item on the bill. Nothing to do here.")
    ws0.row_dimensions[6].height = 30
    guide_status_row(7, "FAIL", "We looked for this on the bill and couldn't find it. This is the one worth a real look — sometimes it's a genuine gap, and sometimes a brand just phrases things differently than we expected (both happen — see \"A few real examples\" below).")
    ws0.row_dimensions[7].height = 75
    guide_status_row(8, "REVIEW", "We can't be fully certain from just reading the text. A person should glance at the actual bill for this one item. This is NOT the same as FAIL — it just means the automatic check has a genuine blind spot here.")
    ws0.row_dimensions[8].height = 60
    guide_status_row(9, "SKIP", "This check doesn't apply to this particular bill (for example, a rule that's only relevant to one utility territory, or a barcode that can't be checked by reading text).")
    ws0.row_dimensions[9].height = 60
    guide_status_row(10, "N/A", "Not applicable. This brand does not print this line on this type of bill (for example, Amigo and Tara bills have no separate Base Charge line), so a missing line is expected and is not a problem.")
    ws0.row_dimensions[10].height = 60

    guide_heading(11, "How to find the real problems fast")
    guide_text(12, "1. Go to the \"Results\" tab. 2. Click the small filter arrow on any column header. 3. Uncheck everything except \"FAIL\" text (or type FAIL into the filter search box). 4. That column now shows only the bills with a real problem for that specific item. Repeat for any other column you want to check.")
    guide_text(13, "For the fastest overview instead, go to the \"Summary\" tab first — it lists every check with how many bills passed, failed, needed review, or were skipped, sorted so the most common problems are at the top. Start there before diving into individual bills.")

    guide_heading(15, "A few real examples of what a FAIL might actually mean")
    guide_text(16, "Not every FAIL is a mistake on the bill. While building this tool, we found real cases where a brand simply phrases something differently than we expected — for example, one brand writes \"Acct #\" where we were originally looking for \"Account Number.\" We fix these as we find them, but it means a FAIL is a signal to go look at the real bill, not automatic proof something is wrong.")
    guide_text(17, "One specific case worth knowing: the \"Customer Name / Billing Address\" column will almost always show REVIEW, not PASS. That's because real bills print this information with no label at all - there's nothing for a text search to reliably confirm. This is an honest limitation, not a bug.")
    guide_text(18, "A separate column, \"Customer Name Looks Valid\", checks the printed name itself: FAIL if it is blank or says something like \"test\", and REVIEW if it looks like random letters, is unusually long, or has odd symbols or numbers. The name is not copied into this report.")

    guide_heading(19, "What this report does NOT check")
    guide_text(20, "This only checks whether required information is PRESENT on the bill - not whether the numbers themselves are correct (for example, it confirms an \"average price per kWh\" message exists, but doesn't verify that number is calculated correctly). It also does not check the bill's visual layout - overlapping text, blank pages, or formatting problems are a separate, not-yet-built check.")

    guide_heading(22, "Questions?")
    guide_text(23, "Contact Momna Ali. This tool and report are still being expanded — if something here looks wrong or confusing, that feedback directly helps make the next version better.")

    ws0.column_dimensions["A"].width = 25
    ws0.column_dimensions["B"].width = 90

    ws = wb.create_sheet("Results")

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

    ws.freeze_panes = "F2"
    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}{len(all_results) + 1}"
    ws.column_dimensions["A"].width = 45
    for col_idx in range(2, 6):
        ws.column_dimensions[get_column_letter(col_idx)].width = 14
    for col_idx in range(6, len(headers) + 1):
        ws.column_dimensions[get_column_letter(col_idx)].width = 32
    ws.row_dimensions[1].height = 45

    ws2 = wb.create_sheet("Summary")
    ws2.cell(row=1, column=1, value="Bill PDF Audit - Summary").font = Font(name="Arial", bold=True, size=14)
    ws2.cell(row=2, column=1, value=f"Total bills checked: {len(all_results)}").font = Font(name="Arial")

    summary_headers = ["Check", "Passed", "Failed", "Needs Review", "Skipped", "Not Applicable"]
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
        not_app = sum(1 for r in all_results if r[rule][0] == "N/A")
        counts.append((RULE_LABELS[rule], passed, failed, review, skipped, not_app))

    counts.sort(key=lambda row: row[2], reverse=True)

    for row_idx, (label, passed, failed, review, skipped, not_app) in enumerate(counts, start=5):
        ws2.cell(row=row_idx, column=1, value=label).font = Font(name="Arial")
        fail_cell = ws2.cell(row=row_idx, column=3, value=failed)
        fail_cell.font = Font(name="Arial", bold=(failed > 0), color="9C0006" if failed > 0 else "000000")
        ws2.cell(row=row_idx, column=2, value=passed).font = Font(name="Arial")
        ws2.cell(row=row_idx, column=4, value=review).font = Font(name="Arial")
        ws2.cell(row=row_idx, column=5, value=skipped).font = Font(name="Arial")
        ws2.cell(row=row_idx, column=6, value=not_app).font = Font(name="Arial")

    ws2.column_dimensions["A"].width = 34
    for col in ["B", "C", "D", "E", "F"]:
        ws2.column_dimensions[col].width = 14

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
    skipped_not_in_manifest = []

    for path in pdf_files:
        fname = os.path.basename(path)

        if fname in manifest:
            account_type, territory = manifest[fname]
        else:
            print(f"\n{fname}  -- SKIPPED (not found in manifest, not a real bill)")
            skipped_not_in_manifest.append(fname)
            continue

        results = check_bill(path, account_type, territory)
        if results is None:
            print(f"\n{fname}  -- SKIPPED (check_bill returned no results, likely a PDF text-extraction issue)")
            continue

        print_result(results)
        all_results.append(results)

    total = len(all_results)
    fails = [
        (r["file"], rule)
        for r in all_results
        for rule in PRINT_ORDER
        if r[rule][0] == "FAIL"
    ]
    print(f"\n{'='*60}")
    print(f"SUMMARY: {total} bills checked, {len(fails)} rule failures found")
    if skipped_not_in_manifest:
        print(f"({len(skipped_not_in_manifest)} PDF(s) in the folder were skipped - not listed in the manifest)")
    print(f"{'='*60}")

    if excel_path and all_results:
        write_excel_report(all_results, excel_path)


# ---------------------------------------------------------------------------
# EASY MODE: point the tool at a folder and it does everything itself.
#   py check_bill_rules_WITH_EXCEL.py --easy "Bills to check"
# It works out residential/commercial and the power company from each bill,
# checks the 8 required messages on English bills, and saves a dated Excel
# report in a "Reports" folder. It only READS the bills. It never changes them.
# ---------------------------------------------------------------------------
import time
from datetime import datetime

UTILITY_PATTERNS = [
    ("Oncor", r"oncor"),
    ("Centerpoint Energy", r"center\s*point"),
    ("AEP Texas", r"\baep\b"),
    ("Texas-New Mexico Power Co", r"tnmp|new mexico"),
    ("Lubbock Power & Light", r"lubbock"),
]
# Backup: the first 7 digits of the service ID show the power company
ESI_PREFIX = {
    "1044372": "Oncor",
    "1017699": "Oncor",
    "1003278": "AEP Texas",
    "1020404": "AEP Texas North",
    "1008901": "Centerpoint Energy",
    "1040051": "Texas-New Mexico Power Co",
    "1011292": "Lubbock Power & Light",
}


def find_utility(text):
    found = [name for name, pat in UTILITY_PATTERNS if re.search(pat, text, re.I)]
    if len(found) == 1:
        return found[0]
    m = re.search(r"#\s*:[^\d\n]*(\d{15,})", text)
    if m and m.group(1)[:7] in ESI_PREFIX:
        return ESI_PREFIX[m.group(1)[:7]]
    return "Unknown"


def find_account_type(text):
    if re.search(r"residential|residencial", text, re.I):
        return "residential"
    return "commercial"


def _easy_setup(messages_only, english_only):
    """Runs once in every worker, so each one uses the same settings."""
    global SKIP_SPANISH
    if messages_only:
        del PRINT_ORDER[8:]
    if english_only:
        SKIP_SPANISH = True


def _easy_one(path):
    """Check one bill. Never crashes: a bad bill comes back as an error note."""
    name = os.path.basename(path)
    try:
        text = extract_text(path)
        if len(text.strip()) < 50:
            return ("error", name, "No readable text in this PDF (it may be a scan or an empty file).")
        res = check_bill(path, find_account_type(text), find_utility(text), text=text)
        if res is None:
            return ("error", name, "The tool could not read this bill.")
        return ("ok", name, res)
    except Exception as e:
        return ("error", name, f"Could not open this PDF: {e}")


def run_easy(folder, out_folder="Reports", all_checks=False, workers=None):
    start = time.time()
    if not os.path.isdir(folder):
        print(f"I cannot find the folder '{folder}'. Check the name and try again.")
        return
    pdfs = sorted(glob.glob(os.path.join(folder, "**", "*.pdf"), recursive=True))
    pdfs += sorted(glob.glob(os.path.join(folder, "**", "*.PDF"), recursive=True))
    pdfs = sorted(set(pdfs))
    if not pdfs:
        print(f"There are no PDF bills in '{folder}'. Nothing to check.")
        return

    names = [os.path.basename(p) for p in pdfs]
    dupes = sorted({n for n in names if names.count(n) > 1})
    if dupes:
        print(f"Heads up: {len(dupes)} file name(s) appear more than once, for example {dupes[0]}.")
        print("Each one is still checked, but the report will show them with the same name.")

    messages_only = not all_checks
    print(f"Checking {len(pdfs)} bills. This can take a few minutes. Nothing is changed in the bills.")
    _easy_setup(messages_only, True)   # also applies to this process

    ok, errors = [], []
    done = 0
    workers = workers or max(1, min(8, (os.cpu_count() or 2) - 1))
    try:
        if workers > 1 and len(pdfs) > 20:
            from multiprocessing import Pool
            with Pool(workers, initializer=_easy_setup, initargs=(messages_only, True)) as pool:
                for kind, name, payload in pool.imap(_easy_one, pdfs, chunksize=10):
                    (ok if kind == "ok" else errors).append((name, payload))
                    done += 1
                    if done % 100 == 0:
                        print(f"  {done} of {len(pdfs)} done")
        else:
            for p in pdfs:
                kind, name, payload = _easy_one(p)
                (ok if kind == "ok" else errors).append((name, payload))
                done += 1
                if done % 100 == 0:
                    print(f"  {done} of {len(pdfs)} done")
    except KeyboardInterrupt:
        print("Stopped. No report was saved.")
        return

    results = [r for _n, r in ok]
    os.makedirs(out_folder, exist_ok=True)
    stamp = datetime.now().strftime("%Y-%m-%d_%H%M")
    report = os.path.join(out_folder, f"bill_audit_report_{stamp}.xlsx")
    if results:
        write_excel_report(results, report)

    if errors:
        err_path = os.path.join(out_folder, f"bills_that_could_not_be_checked_{stamp}.csv")
        with open(err_path, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["bill", "what_went_wrong"])
            w.writerows(errors)

    fails = sum(1 for r in results for rule in PRINT_ORDER if r[rule][0] == "FAIL")
    reviews = sum(1 for r in results for rule in PRINT_ORDER if r[rule][0] == "REVIEW")
    spanish = sum(1 for r in results if all(r[rule][1].startswith("Spanish bill") for rule in PRINT_ORDER))
    mins = (time.time() - start) / 60
    print("\n" + "=" * 60)
    print(f"Bills found:              {len(pdfs)}")
    print(f"Checked:                  {len(results)}  (Spanish bills skipped for now: {spanish})")
    print(f"Missing a required item:  {fails}")
    print(f"Needs a quick look:       {reviews}")
    print(f"Could not be checked:     {len(errors)}")
    print(f"Time taken:               {mins:.1f} minutes")
    if results:
        print(f"Report saved:             {report}")
    if errors:
        print(f"List of problem bills:    {err_path}")
    print("=" * 60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Bill PDF Audit Tool - Phase 1 rule checker")
    parser.add_argument("pdf", nargs="?", help="Path to a single PDF to check")
    parser.add_argument("--account-type", choices=["residential", "commercial"], help="Account type for single-file mode")
    parser.add_argument("--territory", help="Utility territory for single-file mode (Centerpoint/Oncor/AEP/TNMP/Lubbock)")
    parser.add_argument("--batch", help="Folder to batch-check (recursively finds all PDFs)")
    parser.add_argument("--manifest", help="Optional CSV with columns: filename,account_type,territory")
    parser.add_argument("--excel", help="Optional path to write an Excel report")
    parser.add_argument("--messages-only", action="store_true",
                        help="Only check the 8 required bill messages (Section 1), not the charges or other fields")
    parser.add_argument("--easy", metavar="FOLDER",
                        help="Easiest way to run: give a folder of bills and the tool does the rest (no manifest needed)")
    parser.add_argument("--reports-folder", default="Reports", help="Where --easy saves the report (default: Reports)")
    parser.add_argument("--all-checks", action="store_true", help="With --easy: also run the charges and other checks, not just the 8 messages")
    parser.add_argument("--english-only", action="store_true",
                        help="Mark Spanish bills as SKIP instead of checking them (the tool only knows English wording)")
    args = parser.parse_args()

    if args.easy:
        run_easy(args.easy, args.reports_folder, args.all_checks)
        sys.exit(0)

    if args.messages_only:
        del PRINT_ORDER[8:]          # keep only Section 1, the 8 required messages
    if args.english_only:
        SKIP_SPANISH = True

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