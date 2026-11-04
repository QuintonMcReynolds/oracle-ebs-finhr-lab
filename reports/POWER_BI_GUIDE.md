# Power BI build guide

Start the database and keep it running: `KEEP_DB=1 ./scripts/run_local.sh`

Connection: server `localhost:1521/FREEPDB1`, user `ebslab`, password `LabPassw0rd`.
Power BI's Oracle connector needs the Oracle Client for Microsoft Tools (free from Oracle).

## 1. Paginated report: AP Invoice Exceptions (Power BI Report Builder)

1. Open Power BI Report Builder → **New** → **Blank report** (Letter, landscape).
2. **Data Sources** → Add → Type *Oracle Database* → connection string `localhost:1521/FREEPDB1`.
3. **Dataset** `dsInvoices`:
   ```sql
   SELECT invoice_num, vendor_name, invoice_date, invoice_amount, po_number,
          validation_status, approval_status, open_holds, hold_codes
     FROM xx_ap_invoice_status_v
    WHERE (:p_status = 'ALL' OR validation_status = :p_status)
    ORDER BY invoice_date
   ```
   Parameter `p_status`: available values `ALL`, `VALIDATED`, `NEEDS REVALIDATION`; default `ALL`.
4. **Dataset** `dsRejects`: `SELECT * FROM xx_ap_import_exceptions_v`.
5. Add a **Table** for each dataset. Group `dsInvoices` by `vendor_name` with a subtotal on `invoice_amount`.
6. Conditional fill on `hold_codes`: `=IIF(Fields!open_holds.Value > 0, "MistyRose", "White")`.
7. Header: report title, `=Parameters!p_status.Value`, and `=Globals!ExecutionTime`. Footer: `Page N of M`.
8. Save as `AP_Invoice_Exceptions.rdl` and publish to a Power BI workspace (needs Premium/PPU/Fabric capacity).

## 2. Paginated report: GL Trial Balance

Dataset: `SELECT * FROM xx_gl_trial_balance_v WHERE period_name = :p_period ORDER BY account`
Parameter `p_period` (default `OCT-26`). One table with a total row; add an expression that
shows **OUT OF BALANCE** in red when `Sum(total_dr) <> Sum(total_cr)`.

## 3. Desktop dashboard: Finance and HR overview

Power BI Desktop → **Get data → Oracle database** → import these views:
`xx_ap_aging_v`, `xx_ap_invoice_status_v`, `xx_hxc_weekly_hours_v`, `xx_irc_funnel_v`.

| Visual | Fields |
|---|---|
| Card: Open AP | `Sum(xx_ap_aging_v[open_amount])` |
| Stacked bar: AP aging | Axis `aging_bucket`, values `open_amount`, legend `vendor_name` |
| Table: invoices on hold | `xx_ap_invoice_status_v` filtered `open_holds > 0` |
| Column: hours by week | Axis `period_start`, values `total_hours`, `overtime_hours` |
| Funnel: applicants | Group `status`, values `applicants` |

DAX measure for overtime share:
```
OT % = DIVIDE ( SUM ( xx_hxc_weekly_hours_v[overtime_hours] ),
                SUM ( xx_hxc_weekly_hours_v[total_hours] ) )
```

Save as `Finance_HR_Overview.pbix`.
