# SSP Document Schema

This document describes the Excel file format expected when uploading a **System Security Plan (SSP)** into SPARC.

---

## Overview

SPARC parses SSP Excel files row-by-row, mapping each row to a security control. Column headers are matched case-insensitively and trimmed of whitespace, so minor formatting differences are tolerated. The parser uses the first worksheet in the workbook.

---

## Required Columns

| Column Name | Accepted Header Variations | Required | Description |
|-------------|---------------------------|----------|-------------|
| `control_id` | `Control ID`, `Control Identifier`, `ID` | **Yes** | NIST control identifier (e.g., `AC-1`, `AC-2(1)`) |
| `title` | `Control Title`, `Title`, `Control Name` | **Yes** | Human-readable control name |

Rows missing `control_id` are skipped. Rows missing `title` are imported with a blank title.

---

## Optional Columns

These columns are parsed and stored as control fields. Fields in the **Editable** column can be updated inline in the SPARC editor; all others are read-only after import.

| Column Name | Accepted Header Variations | Editable | Description |
|-------------|---------------------------|----------|-------------|
| `implementation_status` | `Implementation Status`, `Status` | **Yes** | Current implementation state of the control |
| `responsible_role` | `Responsible Role`, `Role` | **Yes** | Role or team responsible for the control |
| `control_origination` | `Control Origination`, `Origination` | **Yes** | How the control is satisfied (system-specific, inherited, hybrid) |
| `customer_responsibility` | `Customer Responsibility`, `Responsibility` | **Yes** | What the customer is responsible for, if anything |
| `implementation_guidance` | `Implementation Guidance`, `Guidance` | **Yes** | Free-text narrative describing how the control is implemented |

> **Note:** Column order does not matter. Null or blank values are stored as empty strings.

---

## Valid `implementation_status` Values

The SSP heat map and filtering use these exact status values. Ensure consistent casing.

| Value | Heat Map Color | Description |
|-------|---------------|-------------|
| `Implemented` | Green | Control is fully implemented |
| `Partially Implemented` | Orange | Control is partially in place |
| `Planned` | Blue | Implementation is planned but not yet in place |
| `Alternative Implementation` | Purple | An approved alternative satisfies the control |
| `Not Applicable` | Gray | Control does not apply to this system |
| `Not Implemented` | Red | Control is not implemented (open finding) |

Any value not in the table above will still import and display, but will not match the default color mapping.

---

## Valid `control_origination` Values

These are conventional values; SPARC does not validate origination text.

| Value | Description |
|-------|-------------|
| `System Specific` | The system owner is solely responsible for implementing the control |
| `Inherited` | Control is fully inherited from a common control provider |
| `Hybrid` | Control is partially inherited and partially system-specific |
| `Common Control Provider` | Control is provided as a common control to multiple systems |

---

## Example File Layout

| Control ID | Control Title | Responsible Role | Implementation Status | Control Origination | Customer Responsibility | Implementation Guidance |
|------------|--------------|------------------|-----------------------|---------------------|------------------------|------------------------|
| AC-1 | Policy and Procedures | CISO | Implemented | System Specific | None | Policy POL-AC-001 is reviewed annually and approved by the CISO. |
| AC-2 | Account Management | System Administrator | Implemented | System Specific | None | Accounts provisioned via HR workflow; quarterly access reviews conducted. |
| AC-4 | Information Flow Enforcement | Security Engineer | Partially Implemented | Hybrid | Agency responsible for data labels | Network controls in place. Application-level DLP labeling in progress. |
| AC-6 | Least Privilege | System Administrator | Planned | System Specific | None | Privilege review tool selected; deployment scheduled for Q2. |
| AC-18 | Wireless Access | IT Operations | Not Applicable | System Specific | None | System is cloud-hosted with no wireless access points in scope. |

---

## Processing Behavior

- **Header detection:** The parser reads row 1 as the header row. All subsequent rows are treated as data.
- **Blank rows:** Rows where `control_id` is empty or nil are skipped.
- **Duplicate controls:** If the same `control_id` appears more than once in a file, the last row wins.
- **Background processing:** SSP files are processed asynchronously via Sidekiq. The document status transitions from `pending` → `processing` → `completed` (or `failed`). Refresh the page to see updates.
- **Re-upload:** Uploading a new file creates a new SSP document record; it does not overwrite an existing one.

---

## Programmatic Import (API)

SSP documents can also be created via the REST API:

```
POST /api/v1/ssp_documents/convert
Content-Type: multipart/form-data

file=<your_excel_file.xlsx>
```

See the API documentation for full request/response details.

---

## Exporting SSP Data

Any SSP document can be exported as structured JSON from the document show page or via:

```
GET /api/v1/ssp_documents/:id/export
```

The JSON structure mirrors the Excel format with all control fields preserved.
