-- XX_GL_PKG
-- Creates a GL journal from accounted Payables invoices (Create Accounting /
-- Transfer to GL, simplified) and posts it only if debits equal credits.

CREATE OR REPLACE PACKAGE xx_gl_pkg AS
  c_ap_liability_ccid CONSTANT NUMBER := 2;

  -- returns the new je_header_id, or NULL when nothing was eligible
  FUNCTION  create_ap_journal (p_period_name VARCHAR2) RETURN NUMBER;
  PROCEDURE post_journal      (p_je_header_id NUMBER);
END xx_gl_pkg;
/

CREATE OR REPLACE PACKAGE BODY xx_gl_pkg AS

  FUNCTION create_ap_journal (p_period_name VARCHAR2) RETURN NUMBER IS
    l_header_id NUMBER;
    l_line_num  NUMBER := 0;
    l_dr        NUMBER := 0;
    l_cr        NUMBER := 0;
  BEGIN
    FOR inv IN (SELECT i.invoice_id, i.invoice_num, i.invoice_amount
                  FROM ap_invoices_all i
                 WHERE i.validation_status = 'VALIDATED'
                   AND i.approval_status   = 'APPROVED'
                   AND i.posted_flag       = 'N'
                   AND xx_ap_match_pkg.open_hold_count(i.invoice_id) = 0
                   AND TO_CHAR(i.invoice_date, 'MON-YY', 'NLS_DATE_LANGUAGE=ENGLISH') = UPPER(p_period_name)
                 ORDER BY i.invoice_id)
    LOOP
      IF l_header_id IS NULL THEN
        INSERT INTO gl_je_headers (je_source, je_category, period_name)
        VALUES ('Payables', 'Purchase Invoices', UPPER(p_period_name))
        RETURNING je_header_id INTO l_header_id;
      END IF;

      -- Debit expense for each invoice line
      FOR ln IN (SELECT line_number, amount, dist_code_combination_id
                   FROM ap_invoice_lines_all
                  WHERE invoice_id = inv.invoice_id
                  ORDER BY line_number) LOOP
        IF ln.dist_code_combination_id IS NULL THEN
          RAISE_APPLICATION_ERROR(-20021, 'Invoice ' || inv.invoice_num || ' line ' || ln.line_number
                                          || ' has no distribution account');
        END IF;
        l_line_num := l_line_num + 1;
        INSERT INTO gl_je_lines (je_header_id, je_line_num, code_combination_id, entered_dr, entered_cr,
                                 description, reference_1)
        VALUES (l_header_id, l_line_num, ln.dist_code_combination_id, ln.amount, NULL,
                'AP invoice line ' || ln.line_number, inv.invoice_num);
        l_dr := l_dr + ln.amount;
      END LOOP;

      -- Credit AP liability for the invoice total
      l_line_num := l_line_num + 1;
      INSERT INTO gl_je_lines (je_header_id, je_line_num, code_combination_id, entered_dr, entered_cr,
                               description, reference_1)
      VALUES (l_header_id, l_line_num, c_ap_liability_ccid, NULL, inv.invoice_amount,
              'AP liability', inv.invoice_num);
      l_cr := l_cr + inv.invoice_amount;

      UPDATE ap_invoices_all SET posted_flag = 'Y' WHERE invoice_id = inv.invoice_id;
    END LOOP;

    IF l_header_id IS NOT NULL THEN
      UPDATE gl_je_headers
         SET running_total_dr = l_dr, running_total_cr = l_cr
       WHERE je_header_id = l_header_id;
    END IF;

    RETURN l_header_id;
  END create_ap_journal;

  PROCEDURE post_journal (p_je_header_id NUMBER) IS
    l_dr     NUMBER;
    l_cr     NUMBER;
    l_status gl_je_headers.status%TYPE;
  BEGIN
    SELECT status INTO l_status FROM gl_je_headers WHERE je_header_id = p_je_header_id FOR UPDATE;
    IF l_status = 'P' THEN
      RAISE_APPLICATION_ERROR(-20022, 'Journal ' || p_je_header_id || ' is already posted');
    END IF;

    SELECT NVL(SUM(entered_dr), 0), NVL(SUM(entered_cr), 0) INTO l_dr, l_cr
      FROM gl_je_lines
     WHERE je_header_id = p_je_header_id;

    IF l_dr <> l_cr THEN
      RAISE_APPLICATION_ERROR(-20020, 'Journal out of balance: DR ' || l_dr || ' CR ' || l_cr);
    END IF;

    UPDATE gl_je_headers SET status = 'P' WHERE je_header_id = p_je_header_id;
  END post_journal;

END xx_gl_pkg;
/
