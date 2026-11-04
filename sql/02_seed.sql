-- Seed data: every row is fictional and exists to exercise a specific rule.

-- GL accounts  (fund . agency/cost center . natural account)
-- Cash
INSERT INTO gl_code_combinations VALUES (1, '100', '15100', '101000', 'A', 'Y');
-- AP Liability
INSERT INTO gl_code_combinations VALUES (2, '100', '15100', '201000', 'L', 'Y');
-- Office Supplies
INSERT INTO gl_code_combinations VALUES (3, '100', '15100', '521000', 'E', 'Y');
-- IT Services
INSERT INTO gl_code_combinations VALUES (4, '100', '15100', '522000', 'E', 'Y');

-- Suppliers
INSERT INTO ap_suppliers VALUES (1001, 'Acme Office Supply',       'Y');
INSERT INTO ap_suppliers VALUES (1002, 'Blue Ridge IT Services',   'Y');
INSERT INTO ap_suppliers VALUES (1003, 'Old Dominion Paper (inactive)', 'N');

-- Purchase orders
INSERT INTO po_headers_all VALUES (5001, 'PO-5001', 1001, 'APPROVED');
INSERT INTO po_lines_all   VALUES (50011, 5001, 1, 'Copy paper (case)', 100,  5, 3);
INSERT INTO po_lines_all   VALUES (50012, 5001, 2, 'Toner cartridge',    10, 80, 3);
INSERT INTO po_headers_all VALUES (5002, 'PO-5002', 1002, 'APPROVED');
INSERT INTO po_lines_all   VALUES (50021, 5002, 1, 'Consulting hours',   40, 95, 4);

-- Receipts (toner only partially received -> should trigger a QTY REC hold)
INSERT INTO rcv_transactions VALUES (1, 50011, 'RECEIVE', 100, DATE '2026-10-01');
INSERT INTO rcv_transactions VALUES (2, 50012, 'RECEIVE',   6, DATE '2026-10-01');
INSERT INTO rcv_transactions VALUES (3, 50021, 'RECEIVE',  40, DATE '2026-10-03');

-- Invoices arriving through the open interface
-- 9001: valid, but toner line bills 10 when only 6 received   -> imports, QTY REC hold
INSERT INTO ap_invoices_interface VALUES (9001, 'INV-A100', 1001, DATE '2026-10-05', 1300, 'PO-5001', 'NEW');
INSERT INTO ap_invoice_lines_interface VALUES (9001, 1, 1, 100,  5, 500);
INSERT INTO ap_invoice_lines_interface VALUES (9001, 2, 2,  10, 80, 800);
-- 9002: clean 3-way match                                    -> imports, validates, approves, posts
INSERT INTO ap_invoices_interface VALUES (9002, 'INV-B200', 1002, DATE '2026-10-06', 3800, 'PO-5002', 'NEW');
INSERT INTO ap_invoice_lines_interface VALUES (9002, 1, 1,  40, 95, 3800);
-- 9003: inactive supplier                                    -> rejected
INSERT INTO ap_invoices_interface VALUES (9003, 'INV-C300', 1003, DATE '2026-10-06',  250, NULL, 'NEW');
INSERT INTO ap_invoice_lines_interface VALUES (9003, 1, NULL, NULL, NULL, 250);
-- 9004: header amount does not equal sum of lines            -> rejected
INSERT INTO ap_invoices_interface VALUES (9004, 'INV-D400', 1001, DATE '2026-10-07',  999, 'PO-5001', 'NEW');
INSERT INTO ap_invoice_lines_interface VALUES (9004, 1, 1, 100,  5, 500);
-- 9005: duplicate of INV-A100 for the same supplier          -> rejected
INSERT INTO ap_invoices_interface VALUES (9005, 'INV-A100', 1001, DATE '2026-10-08', 1300, 'PO-5001', 'NEW');
INSERT INTO ap_invoice_lines_interface VALUES (9005, 1, 1, 100,  5, 500);
INSERT INTO ap_invoice_lines_interface VALUES (9005, 2, 2,  10, 80, 800);
-- 9006: unit price 99 vs PO 95 (4.2% > 2% tolerance)         -> imports, PRICE hold
INSERT INTO ap_invoices_interface VALUES (9006, 'INV-E500', 1002, DATE '2026-10-09', 3960, 'PO-5002', 'NEW');
INSERT INTO ap_invoice_lines_interface VALUES (9006, 1, 1,  40, 99, 3960);

-- HR: people and assignments (date-tracked, like EBS)
INSERT INTO per_all_people_f VALUES (1, DATE '2020-01-01', DATE '4712-12-31', 'E001', 'Reyes, Dana');
INSERT INTO per_all_people_f VALUES (2, DATE '2018-06-01', DATE '4712-12-31', 'E002', 'Lee, Marcus');
INSERT INTO per_all_people_f VALUES (3, DATE '2023-03-15', DATE '4712-12-31', 'E003', 'Shah, Priya');
INSERT INTO per_all_assignments_f VALUES (11, 1, DATE '2020-01-01', DATE '4712-12-31', 2,    'AP Manager',        5000,  'Y');
INSERT INTO per_all_assignments_f VALUES (12, 2, DATE '2018-06-01', DATE '4712-12-31', NULL, 'Finance Director', 50000,  'Y');
INSERT INTO per_all_assignments_f VALUES (13, 3, DATE '2023-03-15', DATE '4712-12-31', 1,    'Accounts Payable Technician', 0, 'N');

-- Time and Labor
-- 7001: clean 40-hour week
INSERT INTO hxc_timecards VALUES (7001, 3, DATE '2026-10-05', DATE '2026-10-11', 'SUBMITTED');
INSERT INTO hxc_time_entries VALUES (7001, DATE '2026-10-05', 8, 'REGULAR');
INSERT INTO hxc_time_entries VALUES (7001, DATE '2026-10-06', 8, 'REGULAR');
INSERT INTO hxc_time_entries VALUES (7001, DATE '2026-10-07', 8, 'REGULAR');
INSERT INTO hxc_time_entries VALUES (7001, DATE '2026-10-08', 8, 'REGULAR');
INSERT INTO hxc_time_entries VALUES (7001, DATE '2026-10-09', 8, 'REGULAR');
-- 7002: 46 hours for a non-exempt employee -> valid, 6 hours overtime
INSERT INTO hxc_timecards VALUES (7002, 3, DATE '2026-10-12', DATE '2026-10-18', 'SUBMITTED');
INSERT INTO hxc_time_entries VALUES (7002, DATE '2026-10-12', 10, 'REGULAR');
INSERT INTO hxc_time_entries VALUES (7002, DATE '2026-10-13', 10, 'REGULAR');
INSERT INTO hxc_time_entries VALUES (7002, DATE '2026-10-14', 10, 'REGULAR');
INSERT INTO hxc_time_entries VALUES (7002, DATE '2026-10-15', 10, 'REGULAR');
INSERT INTO hxc_time_entries VALUES (7002, DATE '2026-10-16',  6, 'REGULAR');
-- 7003: two errors: 25 hours in one day, and a date outside the period
INSERT INTO hxc_timecards VALUES (7003, 3, DATE '2026-10-19', DATE '2026-10-25', 'SUBMITTED');
INSERT INTO hxc_time_entries VALUES (7003, DATE '2026-10-19', 25, 'REGULAR');
INSERT INTO hxc_time_entries VALUES (7003, DATE '2026-10-27',  8, 'REGULAR');

-- iRecruitment
INSERT INTO irc_vacancies VALUES (801, 'VAC-801', 'Accounts Payable Technician', 'APPROVED', DATE '2026-09-01');
INSERT INTO irc_applications VALUES (1, 801, 'Applicant A', 'APPLIED',   DATE '2026-09-03');
INSERT INTO irc_applications VALUES (2, 801, 'Applicant B', 'SCREENED',  DATE '2026-09-05');
INSERT INTO irc_applications VALUES (3, 801, 'Applicant C', 'INTERVIEW', DATE '2026-09-10');
INSERT INTO irc_applications VALUES (4, 801, 'Applicant D', 'OFFER',     DATE '2026-09-18');
INSERT INTO irc_applications VALUES (5, 801, 'Applicant E', 'HIRED',     DATE '2026-09-25');
INSERT INTO irc_applications VALUES (6, 801, 'Applicant F', 'REJECTED',  DATE '2026-09-08');

COMMIT;
