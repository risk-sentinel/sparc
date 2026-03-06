# SAR Document Schema

This document describes the Excel file format expected when uploading a **Security Assessment Results (SAR)** into SPARC.

---

## Overview

SPARC parses SAR Excel files row-by-row, mapping each row to a tested security control. Column headers are matched case-insensitively and trimmed of whitespace. The parser uses the first worksheet in the workbook.

SAR files are processed **synchronously** (unlike SSP files, which use a background job). The document is ready immediately after upload.

---

## Required Columns

| Column Name | Accepted Header Variations | Required | Description |
|-------------|---------------------------|----------|-------------|
| `control_id` | `Control ID`, `Control Identifier`, `ID` | **Yes** | NIST control identifier (e.g., `AC-1`, `AU-6`) |
| `title` | `Control Title`, `Title`, `Control Name` | **Yes** | Human-readable control name |

Rows missing `control_id` are skipped.

---

## Optional Columns

These columns are parsed and stored as control fields. All SAR fields are editable after import.

| Column Name | Accepted Header Variations | Description |
|-------------|---------------------------|-------------|
| `test_status` | `Test Status`, `Status` | Result of the test (Pass, Fail, Partial, etc.) |
| `test_date` | `Test Date`, `Date Tested` | Date the test was performed |
| `tester_name` | `Tester Name`, `Tester`, `Tested By` | Name of the individual who performed the test |
| `test_results` | `Test Results`, `Results`, `Findings` | Narrative description of what was tested and observed |
| `remediation_plan` | `Remediation Plan`, `Remediation`, `Action Plan` | Corrective action plan for controls that did not pass |

> **Note:** Column order does not matter. Null or blank values are stored as empty strings.

---

## Valid `test_status` Values

The SAR heat map and filtering use these exact status values. Ensure consistent casing.

| Value | Heat Map Color | Description |
|-------|---------------|-------------|
| `Pass` | Green | Control met all test objectives |
| `Partial` | Orange | Control partially met test objectives |
| `Fail` | Red | Control did not meet test objectives (open finding) |
| `Not Tested` | Gray | Control was not tested in this assessment cycle |
| `Not Applicable` | Light Gray | Control does not apply and was not assessed |

Any value not in the table above will still import and display, but will not match the default color mapping.

---

## `test_date` Format

Dates are stored as plain text. Recommended formats:

| Format | Example |
|--------|---------|
| ISO 8601 | `2025-10-15` |
| US long form | `October 15, 2025` |
| Short US | `10/15/2025` |

SPARC does not parse or validate the date format; it is stored and displayed as entered.

---

## Example File Layout

| Control ID | Control Title | Test Status | Test Date | Tester Name | Test Results | Remediation Plan |
|------------|--------------|-------------|-----------|-------------|--------------|-----------------|
| AC-1 | Policy and Procedures | Pass | 2025-10-15 | J. Smith | Policy documentation reviewed; current version dated September 2025. Approved by CISO. | |
| AC-4 | Information Flow Enforcement | Partial | 2025-10-17 | A. Patel | Network-level flow controls verified. Application DLP labeling incomplete on 3 data paths. | Complete application-level DLP labeling by Q1 2026. Track in POA&M AC-4-001. |
| AC-6 | Least Privilege | Partial | 2025-10-18 | A. Patel | OS and application privileges verified. Four service accounts with excessive privilege identified. | Reduce privilege on SA-DB-01, SA-APP-03, SA-NET-02, SA-MON-01 by December 2025. |
| AU-6 | Audit Record Review | Not Tested | | | Automated review capability not yet deployed; scheduled for Q1 2026. | Deploy automated audit review reporting by March 2026. Track in POA&M AU-6-001. |
| CA-7 | Continuous Monitoring | Not Tested | | | Configuration drift detection not yet implemented. | Deploy configuration drift tooling by June 2026. |
| CP-4 | Contingency Plan Testing | Not Tested | | | Full failover test not conducted for current environment version. | Conduct full failover test by June 2026. |
| AC-14 | Permitted Actions Without Auth | Not Applicable | 2025-10-20 | J. Smith | Not applicable — all system functions require authentication. | |

---

## Relationship to SSP Documents

SAR documents are independent of SSP documents in the database — they share `control_id` values but are not linked by foreign key. A typical workflow:

1. Upload an SSP documenting how controls are implemented
2. Upload a SAR documenting test results for those same controls
3. Use the heat maps on each document to compare implementation status vs. test results

---

## Processing Behavior

- **Header detection:** Row 1 is the header row. All subsequent rows are data.
- **Blank rows:** Rows with an empty `control_id` are skipped.
- **Synchronous processing:** SAR files are parsed immediately on upload; no background job is required.
- **Re-upload:** Uploading a new file always creates a new SAR document record.

---

## Programmatic Import (API)

SAR documents can be created via the REST API:

```
POST /api/v1/sar_documents/convert
Content-Type: multipart/form-data

file=<your_excel_file.xlsx>
```

---

## Exporting SAR Data

Any SAR document can be exported as structured JSON from the document show page or via:

```
GET /api/v1/sar_documents/:id/export
```
