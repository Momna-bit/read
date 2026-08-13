	
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

