-- End-to-end test: import -> validate -> approve -> GL journal -> post,
-- plus Time and Labor validation. Any failed assertion raises ORA-20999
-- and SQL*Plus exits non-zero, which fails the CI pipeline.

SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

CREATE OR REPLACE PROCEDURE assert_eq (p_label VARCHAR2, p_expected VARCHAR2, p_actual VARCHAR2) IS
BEGIN
  IF NVL(p_expected, '~null~') <> NVL(p_actual, '~null~') THEN
    RAISE_APPLICATION_ERROR(-20999, 'FAIL ' || p_label || ': expected [' || p_expected
                                    || '] got [' || p_actual || ']');
  END IF;
  DBMS_OUTPUT.PUT_LINE('PASS ' || p_label);
END;
/

DECLARE
  l_imported NUMBER;
  l_rejected NUMBER;
  l_text     VARCHAR2(400);
  l_num      NUMBER;
  l_approver NUMBER;
  l_je       NUMBER;
BEGIN
  ---------------------------------------------------------------- AP import
  xx_ap_import_pkg.run_import(l_imported, l_rejected);
  assert_eq('import: imported count', '3', l_imported);
  assert_eq('import: rejected count', '3', l_rejected);

  SELECT reject_lookup_code INTO l_text FROM ap_interface_rejections WHERE parent_id = 9003;
  assert_eq('import: inactive supplier', 'INACTIVE SUPPLIER', l_text);
  SELECT reject_lookup_code INTO l_text FROM ap_interface_rejections WHERE parent_id = 9004;
  assert_eq('import: amount mismatch', 'INVOICE AMOUNT MISMATCH', l_text);
  SELECT reject_lookup_code INTO l_text FROM ap_interface_rejections WHERE parent_id = 9005;
  assert_eq('import: duplicate', 'DUPLICATE INVOICE', l_text);

  SELECT dist_code_combination_id INTO l_num FROM ap_invoice_lines_all
   WHERE invoice_id = 9002 AND line_number = 1;
  assert_eq('import: distribution defaulted from PO charge account', '4', l_num);

  ---------------------------------------------------------------- 3-way match
  xx_ap_match_pkg.validate_all;

  SELECT validation_status INTO l_text FROM ap_invoices_all WHERE invoice_id = 9002;
  assert_eq('match: clean invoice validated', 'VALIDATED', l_text);

  SELECT hold_codes INTO l_text FROM xx_ap_invoice_status_v WHERE invoice_id = 9001;
  assert_eq('match: partial receipt -> QTY REC hold', 'QTY REC', l_text);

  SELECT hold_codes INTO l_text FROM xx_ap_invoice_status_v WHERE invoice_id = 9006;
  assert_eq('match: price over tolerance -> PRICE hold', 'PRICE', l_text);

  ---------------------------------------------------------------- approval
  BEGIN
    l_approver := xx_ap_approval_pkg.initiate(9001, 3);
    assert_eq('approval: held invoice blocked', 'error expected', 'no error');
  EXCEPTION
    WHEN OTHERS THEN
      assert_eq('approval: held invoice blocked', '-20010', TO_CHAR(SQLCODE));
  END;

  l_approver := xx_ap_approval_pkg.initiate(9002, 3);   -- requester: AP technician
  assert_eq('approval: routed to AP manager (limit 5000)', '1', l_approver);
  xx_ap_approval_pkg.respond(9002, 1, 'APPROVED');
  SELECT approval_status INTO l_text FROM ap_invoices_all WHERE invoice_id = 9002;
  assert_eq('approval: approved', 'APPROVED', l_text);

  ---------------------------------------------------------------- receipt fixes hold
  INSERT INTO rcv_transactions VALUES (4, 50012, 'RECEIVE', 4, DATE '2026-10-10');
  xx_ap_match_pkg.validate_invoice(9001);
  SELECT validation_status INTO l_text FROM ap_invoices_all WHERE invoice_id = 9001;
  assert_eq('match: remaining toner received -> revalidates', 'VALIDATED', l_text);
  l_approver := xx_ap_approval_pkg.initiate(9001, 3);
  assert_eq('approval: 1300 also routed to AP manager', '1', l_approver);
  xx_ap_approval_pkg.respond(9001, 1, 'APPROVED');

  ---------------------------------------------------------------- GL
  l_je := xx_gl_pkg.create_ap_journal('OCT-26');
  SELECT running_total_dr || '/' || running_total_cr INTO l_text FROM gl_je_headers WHERE je_header_id = l_je;
  assert_eq('gl: journal totals (9001 + 9002, 9006 still on hold)', '5100/5100', l_text);
  xx_gl_pkg.post_journal(l_je);

  SELECT net_balance INTO l_num FROM xx_gl_trial_balance_v WHERE account = '100.15100.201000';
  assert_eq('gl: AP liability balance', '-5100', l_num);
  SELECT net_balance INTO l_num FROM xx_gl_trial_balance_v WHERE account = '100.15100.522000';
  assert_eq('gl: IT services expense', '3800', l_num);

  SELECT posted_flag INTO l_text FROM ap_invoices_all WHERE invoice_id = 9006;
  assert_eq('gl: held invoice not accounted', 'N', l_text);

  ---------------------------------------------------------------- Time and Labor
  xx_hxc_pkg.validate_all;

  SELECT approval_status || ':' || overtime_hours INTO l_text FROM xx_hxc_weekly_hours_v WHERE timecard_id = 7001;
  assert_eq('hxc: 40h week', 'VALIDATED:0', l_text);
  SELECT approval_status || ':' || overtime_hours INTO l_text FROM xx_hxc_weekly_hours_v WHERE timecard_id = 7002;
  assert_eq('hxc: 46h week -> 6h overtime', 'VALIDATED:6', l_text);

  SELECT LISTAGG(error_code, ',') WITHIN GROUP (ORDER BY error_code) INTO l_text
    FROM hxc_validation_errors WHERE timecard_id = 7003;
  assert_eq('hxc: bad timecard errors', 'DATE_OUT_OF_PERIOD,HOURS_EXCEED_24', l_text);

  ---------------------------------------------------------------- iRecruitment
  SELECT SUM(applicants) INTO l_num FROM xx_irc_funnel_v WHERE vacancy = 'VAC-801';
  assert_eq('irc: funnel total', '6', l_num);

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('ALL TESTS PASSED');
END;
/
EXIT SUCCESS
