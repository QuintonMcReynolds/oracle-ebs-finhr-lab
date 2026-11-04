# Design notes (systems analysis)

## Problem
Payables staff need invoices from outside feeds loaded without bad data reaching the
ledger, invoices paid only for goods actually ordered and received at the agreed price,
approvals routed by authority level, and finance and HR reporting from one source.

## Requirements → implementation

| # | Requirement | Where |
|---|---|---|
| R1 | Reject staged invoices with a clear reason; never partially load one | `XX_AP_IMPORT_PKG.run_import`, `AP_INTERFACE_REJECTIONS` |
| R2 | Block payment until billed qty ≤ received qty and price is within 2% of PO | `XX_AP_MATCH_PKG`, `AP_HOLDS_ALL` |
| R3 | Re-validate automatically when receipts arrive | `validate_invoice` clears and re-evaluates system holds |
| R4 | Approver = first manager up the chain with enough authority | `XX_AP_APPROVAL_PKG.initiate` (hierarchical query) |
| R5 | Only validated, approved, hold-free invoices reach the GL; journals must balance | `XX_GL_PKG` |
| R6 | Timecards: ≤ 24 h/day, no negatives, dates inside the period; overtime > 40 h for non-exempt | `XX_HXC_PKG` |
| R7 | Paginated and dashboard reporting | `sql/03_reporting_views.sql`, `reports/` |

## Process flow (swimlane outline, drawn in Visio for the full version)

1. **Feed** → rows land in `AP_INVOICES_INTERFACE`.
2. **AP Technician** runs import → rejections reviewed in the exceptions report.
3. **System** runs validation → holds placed / released.
4. **AP Technician** submits for approval → **AP Manager** or **Finance Director** responds.
5. **GL Accountant** creates and posts the journal → trial balance report.

## Design choices
- Date-tracked HR tables (`effective_start_date`/`effective_end_date`) and `SYSDATE BETWEEN` filters, as in EBS.
- Custom objects use the `XX_` prefix so they never collide with seeded Oracle objects.
- Reason codes match Payables lookup codes (`DUPLICATE INVOICE`, `QTY REC`, `PRICE`) so users see familiar values.
- Every seeded row exists to exercise one rule, which keeps the test suite readable.

## Out of scope
Oracle Forms/Reports, JDeveloper/OAF pages, Workflow Builder `.wft` definitions,
multi-org security, payments, and real EBS APIs (`AP_IMPORT_INVOICES_PKG`, `HR_*_API`).
