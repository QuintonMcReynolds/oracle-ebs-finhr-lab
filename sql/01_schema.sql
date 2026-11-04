-- =====================================================================
-- ebs-finhr-lab : simplified Oracle E-Business Suite R12-style data model
-- Modules: Purchasing (PO), Payables (AP), General Ledger (GL),
--          HR (PER), Time and Labor (HXC), iRecruitment (IRC)
-- Table names follow EBS conventions; columns are a trimmed subset.
-- Target: Oracle Database 19c / 23ai (tested in CI on Oracle Database Free)
-- =====================================================================

-- ---------- General Ledger ----------
CREATE TABLE gl_code_combinations (
  code_combination_id NUMBER PRIMARY KEY,
  segment1  VARCHAR2(10) NOT NULL,  -- fund / company
  segment2  VARCHAR2(10) NOT NULL,  -- agency / cost center
  segment3  VARCHAR2(10) NOT NULL,  -- natural account
  account_type CHAR(1) NOT NULL CHECK (account_type IN ('A','L','O','R','E')),
  enabled_flag CHAR(1) DEFAULT 'Y' NOT NULL
);

CREATE TABLE gl_je_headers (
  je_header_id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  je_source      VARCHAR2(25) NOT NULL,
  je_category    VARCHAR2(25) NOT NULL,
  period_name    VARCHAR2(15) NOT NULL,
  status         CHAR(1) DEFAULT 'U' NOT NULL CHECK (status IN ('U','P')), -- Unposted / Posted
  running_total_dr NUMBER DEFAULT 0,
  running_total_cr NUMBER DEFAULT 0,
  creation_date  DATE DEFAULT SYSDATE
);

CREATE TABLE gl_je_lines (
  je_header_id NUMBER NOT NULL REFERENCES gl_je_headers,
  je_line_num  NUMBER NOT NULL,
  code_combination_id NUMBER NOT NULL REFERENCES gl_code_combinations,
  entered_dr   NUMBER,
  entered_cr   NUMBER,
  description  VARCHAR2(240),
  reference_1  VARCHAR2(60),   -- source document (invoice number)
  CONSTRAINT gl_je_lines_pk PRIMARY KEY (je_header_id, je_line_num)
);

-- ---------- Suppliers / Purchasing ----------
CREATE TABLE ap_suppliers (
  vendor_id    NUMBER PRIMARY KEY,
  vendor_name  VARCHAR2(240) NOT NULL,
  enabled_flag CHAR(1) DEFAULT 'Y' NOT NULL
);

CREATE TABLE po_headers_all (
  po_header_id NUMBER PRIMARY KEY,
  segment1     VARCHAR2(20) UNIQUE NOT NULL,   -- PO number
  vendor_id    NUMBER NOT NULL REFERENCES ap_suppliers,
  authorization_status VARCHAR2(25) DEFAULT 'APPROVED'
);

CREATE TABLE po_lines_all (
  po_line_id   NUMBER PRIMARY KEY,
  po_header_id NUMBER NOT NULL REFERENCES po_headers_all,
  line_num     NUMBER NOT NULL,
  item_description VARCHAR2(240),
  quantity     NUMBER NOT NULL,
  unit_price   NUMBER NOT NULL,
  charge_account_id NUMBER NOT NULL REFERENCES gl_code_combinations
);

CREATE TABLE rcv_transactions (
  transaction_id NUMBER PRIMARY KEY,
  po_line_id     NUMBER NOT NULL REFERENCES po_lines_all,
  transaction_type VARCHAR2(25) DEFAULT 'RECEIVE' NOT NULL,
  quantity       NUMBER NOT NULL,
  transaction_date DATE DEFAULT SYSDATE
);

-- ---------- Payables ----------
-- Open interface (staging) – rows land here from a feed, then get imported
CREATE TABLE ap_invoices_interface (
  invoice_id     NUMBER PRIMARY KEY,
  invoice_num    VARCHAR2(50),
  vendor_id      NUMBER,
  invoice_date   DATE,
  invoice_amount NUMBER,
  po_number      VARCHAR2(20),
  status         VARCHAR2(25) DEFAULT 'NEW' NOT NULL     -- NEW / PROCESSED / REJECTED
);

CREATE TABLE ap_invoice_lines_interface (
  invoice_id  NUMBER NOT NULL REFERENCES ap_invoices_interface,
  line_number NUMBER NOT NULL,
  po_line_num NUMBER,
  quantity_invoiced NUMBER,
  unit_price  NUMBER,
  amount      NUMBER,
  CONSTRAINT ap_inv_lines_int_pk PRIMARY KEY (invoice_id, line_number)
);

CREATE TABLE ap_interface_rejections (
  parent_id   NUMBER NOT NULL,
  reject_lookup_code VARCHAR2(30) NOT NULL,
  message     VARCHAR2(400),
  creation_date DATE DEFAULT SYSDATE
);

CREATE TABLE ap_invoices_all (
  invoice_id     NUMBER PRIMARY KEY,
  invoice_num    VARCHAR2(50) NOT NULL,
  vendor_id      NUMBER NOT NULL REFERENCES ap_suppliers,
  invoice_date   DATE NOT NULL,
  invoice_amount NUMBER NOT NULL,
  po_header_id   NUMBER REFERENCES po_headers_all,
  approval_status VARCHAR2(25) DEFAULT 'REQUIRED' NOT NULL, -- REQUIRED/INITIATED/APPROVED/REJECTED
  validation_status VARCHAR2(25) DEFAULT 'NEVER VALIDATED' NOT NULL, -- VALIDATED / NEEDS REVALIDATION
  posted_flag    CHAR(1) DEFAULT 'N' NOT NULL,
  amount_paid    NUMBER DEFAULT 0 NOT NULL,
  CONSTRAINT ap_inv_uk UNIQUE (vendor_id, invoice_num)
);

CREATE TABLE ap_invoice_lines_all (
  invoice_id  NUMBER NOT NULL REFERENCES ap_invoices_all,
  line_number NUMBER NOT NULL,
  po_line_id  NUMBER REFERENCES po_lines_all,
  quantity_invoiced NUMBER,
  unit_price  NUMBER,
  amount      NUMBER NOT NULL,
  dist_code_combination_id NUMBER REFERENCES gl_code_combinations,
  CONSTRAINT ap_inv_lines_pk PRIMARY KEY (invoice_id, line_number)
);

CREATE TABLE ap_holds_all (
  invoice_id  NUMBER NOT NULL REFERENCES ap_invoices_all,
  line_number NUMBER,
  hold_lookup_code VARCHAR2(25) NOT NULL,  -- QTY REC / PRICE / AMOUNT
  hold_reason VARCHAR2(240),
  release_lookup_code VARCHAR2(25),
  hold_date   DATE DEFAULT SYSDATE
);

-- Approval history (what Oracle Workflow / AME would record)
CREATE TABLE ap_inv_aprvl_hist_all (
  approval_history_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  invoice_id NUMBER NOT NULL REFERENCES ap_invoices_all,
  approver_name VARCHAR2(240),
  response   VARCHAR2(25) NOT NULL,   -- SENT / APPROVED / REJECTED / AUTO-APPROVED
  amount_approved NUMBER,
  creation_date DATE DEFAULT SYSDATE
);

-- ---------- HR ----------
CREATE TABLE per_all_people_f (
  person_id   NUMBER NOT NULL,
  effective_start_date DATE NOT NULL,
  effective_end_date   DATE NOT NULL,
  employee_number VARCHAR2(30),
  full_name   VARCHAR2(240) NOT NULL,
  CONSTRAINT per_people_pk PRIMARY KEY (person_id, effective_start_date)
);

CREATE TABLE per_all_assignments_f (
  assignment_id NUMBER NOT NULL,
  person_id     NUMBER NOT NULL,
  effective_start_date DATE NOT NULL,
  effective_end_date   DATE NOT NULL,
  supervisor_id NUMBER,
  job_name      VARCHAR2(240),
  approval_limit NUMBER DEFAULT 0,   -- AP approval authority
  flsa_exempt   CHAR(1) DEFAULT 'N',
  CONSTRAINT per_asg_pk PRIMARY KEY (assignment_id, effective_start_date)
);

-- ---------- Time and Labor (simplified) ----------
CREATE TABLE hxc_timecards (
  timecard_id NUMBER PRIMARY KEY,
  person_id   NUMBER NOT NULL,
  period_start DATE NOT NULL,
  period_end   DATE NOT NULL,
  approval_status VARCHAR2(25) DEFAULT 'SUBMITTED' NOT NULL -- SUBMITTED/VALIDATED/ERROR
);

CREATE TABLE hxc_time_entries (
  timecard_id NUMBER NOT NULL REFERENCES hxc_timecards,
  work_date   DATE NOT NULL,
  hours       NUMBER NOT NULL,
  hours_type  VARCHAR2(25) DEFAULT 'REGULAR' NOT NULL,
  CONSTRAINT hxc_te_pk PRIMARY KEY (timecard_id, work_date, hours_type)
);

CREATE TABLE hxc_validation_errors (
  timecard_id NUMBER NOT NULL,
  error_code  VARCHAR2(30) NOT NULL,
  message     VARCHAR2(400)
);

-- ---------- iRecruitment (simplified) ----------
CREATE TABLE irc_vacancies (
  vacancy_id NUMBER PRIMARY KEY,
  name       VARCHAR2(60) NOT NULL,
  job_name   VARCHAR2(240),
  status     VARCHAR2(25) DEFAULT 'APPROVED',
  date_from  DATE NOT NULL
);

CREATE TABLE irc_applications (
  application_id NUMBER PRIMARY KEY,
  vacancy_id     NUMBER NOT NULL REFERENCES irc_vacancies,
  applicant_name VARCHAR2(240) NOT NULL,
  status         VARCHAR2(25) NOT NULL,  -- APPLIED/SCREENED/INTERVIEW/OFFER/HIRED/REJECTED
  status_date    DATE NOT NULL
);
