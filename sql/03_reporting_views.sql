-- Reporting views: the data sources for the Power BI paginated reports and
-- dashboards described in reports/POWER_BI_GUIDE.md

-- AP invoice status with open holds rolled up
CREATE OR REPLACE VIEW xx_ap_invoice_status_v AS
SELECT i.invoice_id,
       i.invoice_num,
       s.vendor_name,
       i.invoice_date,
       i.invoice_amount,
       p.segment1                AS po_number,
       i.validation_status,
       i.approval_status,
       i.posted_flag,
       (SELECT COUNT(*) FROM ap_holds_all h
         WHERE h.invoice_id = i.invoice_id AND h.release_lookup_code IS NULL) AS open_holds,
       (SELECT LISTAGG(DISTINCT h.hold_lookup_code, ', ') WITHIN GROUP (ORDER BY h.hold_lookup_code)
          FROM ap_holds_all h
         WHERE h.invoice_id = i.invoice_id AND h.release_lookup_code IS NULL) AS hold_codes
  FROM ap_invoices_all i
  JOIN ap_suppliers s ON s.vendor_id = i.vendor_id
  LEFT JOIN po_headers_all p ON p.po_header_id = i.po_header_id;

-- Interface rejections, for the "import exceptions" report
CREATE OR REPLACE VIEW xx_ap_import_exceptions_v AS
SELECT r.parent_id AS interface_invoice_id,
       ii.invoice_num,
       ii.vendor_id,
       ii.invoice_amount,
       r.reject_lookup_code,
       r.message,
       r.creation_date
  FROM ap_interface_rejections r
  JOIN ap_invoices_interface ii ON ii.invoice_id = r.parent_id;

-- AP aging (open balance by age bucket, relative to SYSDATE)
CREATE OR REPLACE VIEW xx_ap_aging_v AS
SELECT s.vendor_name,
       i.invoice_num,
       i.invoice_date,
       i.invoice_amount - i.amount_paid AS open_amount,
       TRUNC(SYSDATE) - i.invoice_date  AS days_old,
       CASE WHEN TRUNC(SYSDATE) - i.invoice_date <= 30 THEN '0-30'
            WHEN TRUNC(SYSDATE) - i.invoice_date <= 60 THEN '31-60'
            WHEN TRUNC(SYSDATE) - i.invoice_date <= 90 THEN '61-90'
            ELSE '90+' END             AS aging_bucket
  FROM ap_invoices_all i
  JOIN ap_suppliers s ON s.vendor_id = i.vendor_id
 WHERE i.invoice_amount - i.amount_paid > 0;

-- GL trial balance from posted journals
CREATE OR REPLACE VIEW xx_gl_trial_balance_v AS
SELECT h.period_name,
       c.segment1 || '.' || c.segment2 || '.' || c.segment3 AS account,
       c.account_type,
       SUM(NVL(l.entered_dr, 0)) AS total_dr,
       SUM(NVL(l.entered_cr, 0)) AS total_cr,
       SUM(NVL(l.entered_dr, 0)) - SUM(NVL(l.entered_cr, 0)) AS net_balance
  FROM gl_je_headers h
  JOIN gl_je_lines l          ON l.je_header_id = h.je_header_id
  JOIN gl_code_combinations c ON c.code_combination_id = l.code_combination_id
 WHERE h.status = 'P'
 GROUP BY h.period_name, c.segment1, c.segment2, c.segment3, c.account_type;

-- Weekly hours by employee with overtime
CREATE OR REPLACE VIEW xx_hxc_weekly_hours_v AS
SELECT t.timecard_id,
       p.full_name,
       t.period_start,
       t.period_end,
       t.approval_status,
       NVL((SELECT SUM(e.hours) FROM hxc_time_entries e WHERE e.timecard_id = t.timecard_id), 0) AS total_hours,
       xx_hxc_pkg.overtime_hours(t.timecard_id) AS overtime_hours
  FROM hxc_timecards t
  JOIN per_all_people_f p
    ON p.person_id = t.person_id
   AND t.period_start BETWEEN p.effective_start_date AND p.effective_end_date;

-- iRecruitment pipeline funnel
CREATE OR REPLACE VIEW xx_irc_funnel_v AS
SELECT v.name AS vacancy,
       v.job_name,
       a.status,
       COUNT(*) AS applicants
  FROM irc_vacancies v
  JOIN irc_applications a ON a.vacancy_id = v.vacancy_id
 GROUP BY v.name, v.job_name, a.status;
