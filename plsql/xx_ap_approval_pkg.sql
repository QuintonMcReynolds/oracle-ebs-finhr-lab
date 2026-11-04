-- XX_AP_APPROVAL_PKG
-- A small version of the AP invoice approval workflow (normally Oracle
-- Workflow + AME). Routes an invoice up the HR supervisor hierarchy to the
-- first person whose approval limit covers the amount, and records history.

CREATE OR REPLACE PACKAGE xx_ap_approval_pkg AS
  c_auto_approve_limit CONSTANT NUMBER := 1000;

  -- returns the person_id that must approve, or NULL if auto-approved
  FUNCTION  initiate (p_invoice_id NUMBER, p_requester_id NUMBER) RETURN NUMBER;
  PROCEDURE respond  (p_invoice_id NUMBER, p_approver_id NUMBER, p_response VARCHAR2);
END xx_ap_approval_pkg;
/

CREATE OR REPLACE PACKAGE BODY xx_ap_approval_pkg AS

  FUNCTION person_name (p_person_id NUMBER) RETURN VARCHAR2 IS
    l_name per_all_people_f.full_name%TYPE;
  BEGIN
    SELECT full_name INTO l_name
      FROM per_all_people_f
     WHERE person_id = p_person_id
       AND SYSDATE BETWEEN effective_start_date AND effective_end_date;
    RETURN l_name;
  END person_name;

  FUNCTION initiate (p_invoice_id NUMBER, p_requester_id NUMBER) RETURN NUMBER IS
    l_amount     ap_invoices_all.invoice_amount%TYPE;
    l_validation ap_invoices_all.validation_status%TYPE;
    l_approver   NUMBER;
    l_name       per_all_people_f.full_name%TYPE;
  BEGIN
    SELECT invoice_amount, validation_status INTO l_amount, l_validation
      FROM ap_invoices_all
     WHERE invoice_id = p_invoice_id;

    IF l_validation <> 'VALIDATED' THEN
      RAISE_APPLICATION_ERROR(-20010, 'Invoice ' || p_invoice_id || ' must be validated before approval');
    END IF;

    IF l_amount <= c_auto_approve_limit THEN
      INSERT INTO ap_inv_aprvl_hist_all (invoice_id, approver_name, response, amount_approved)
      VALUES (p_invoice_id, 'SYSTEM', 'AUTO-APPROVED', l_amount);
      UPDATE ap_invoices_all SET approval_status = 'APPROVED' WHERE invoice_id = p_invoice_id;
      RETURN NULL;
    END IF;

    -- Walk up from the requester's supervisor until approval_limit covers the amount
    BEGIN
      SELECT person_id INTO l_approver
        FROM (SELECT a.person_id, a.approval_limit, LEVEL AS lvl
                FROM per_all_assignments_f a
               WHERE SYSDATE BETWEEN a.effective_start_date AND a.effective_end_date
               START WITH a.person_id = (SELECT s.supervisor_id
                                           FROM per_all_assignments_f s
                                          WHERE s.person_id = p_requester_id
                                            AND SYSDATE BETWEEN s.effective_start_date AND s.effective_end_date)
               CONNECT BY a.person_id = PRIOR a.supervisor_id)
       WHERE approval_limit >= l_amount
       ORDER BY lvl
       FETCH FIRST 1 ROW ONLY;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20011, 'No approver in the hierarchy can approve ' || l_amount);
    END;

    l_name := person_name(l_approver);
    INSERT INTO ap_inv_aprvl_hist_all (invoice_id, approver_name, response, amount_approved)
    VALUES (p_invoice_id, l_name, 'SENT', NULL);
    UPDATE ap_invoices_all SET approval_status = 'INITIATED' WHERE invoice_id = p_invoice_id;
    RETURN l_approver;
  END initiate;

  PROCEDURE respond (p_invoice_id NUMBER, p_approver_id NUMBER, p_response VARCHAR2) IS
    l_pending NUMBER;
    l_amount  NUMBER;
    l_name    per_all_people_f.full_name%TYPE;
  BEGIN
    IF p_response NOT IN ('APPROVED', 'REJECTED') THEN
      RAISE_APPLICATION_ERROR(-20012, 'Response must be APPROVED or REJECTED');
    END IF;

    l_name := person_name(p_approver_id);  -- private function: resolve before using in SQL

    SELECT COUNT(*) INTO l_pending
      FROM ap_inv_aprvl_hist_all h
      JOIN ap_invoices_all i ON i.invoice_id = h.invoice_id
     WHERE h.invoice_id = p_invoice_id
       AND h.response = 'SENT'
       AND h.approver_name = l_name
       AND i.approval_status = 'INITIATED';

    IF l_pending = 0 THEN
      RAISE_APPLICATION_ERROR(-20013, 'No pending approval for this approver');
    END IF;

    SELECT invoice_amount INTO l_amount FROM ap_invoices_all WHERE invoice_id = p_invoice_id;

    INSERT INTO ap_inv_aprvl_hist_all (invoice_id, approver_name, response, amount_approved)
    VALUES (p_invoice_id, l_name, p_response,
            CASE WHEN p_response = 'APPROVED' THEN l_amount END);

    UPDATE ap_invoices_all SET approval_status = p_response WHERE invoice_id = p_invoice_id;
  END respond;

END xx_ap_approval_pkg;
/
