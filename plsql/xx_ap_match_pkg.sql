-- XX_AP_MATCH_PKG
-- Invoice validation with 3-way match (PO price / PO quantity / received quantity).
-- Places holds in AP_HOLDS_ALL the way Invoice Validation does in Payables.

CREATE OR REPLACE PACKAGE xx_ap_match_pkg AS
  c_price_tolerance CONSTANT NUMBER := 0.02;   -- 2% over PO unit price allowed

  PROCEDURE validate_invoice (p_invoice_id NUMBER);
  PROCEDURE validate_all;
  FUNCTION  open_hold_count (p_invoice_id NUMBER) RETURN NUMBER;
END xx_ap_match_pkg;
/

CREATE OR REPLACE PACKAGE BODY xx_ap_match_pkg AS

  PROCEDURE place_hold (p_invoice_id NUMBER, p_line NUMBER, p_code VARCHAR2, p_reason VARCHAR2) IS
  BEGIN
    INSERT INTO ap_holds_all (invoice_id, line_number, hold_lookup_code, hold_reason)
    VALUES (p_invoice_id, p_line, p_code, p_reason);
  END place_hold;

  FUNCTION open_hold_count (p_invoice_id NUMBER) RETURN NUMBER IS
    l_count NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l_count
      FROM ap_holds_all
     WHERE invoice_id = p_invoice_id
       AND release_lookup_code IS NULL;
    RETURN l_count;
  END open_hold_count;

  PROCEDURE validate_invoice (p_invoice_id NUMBER) IS
    l_holds NUMBER;
  BEGIN
    -- Re-validation: system holds are re-evaluated from scratch
    DELETE FROM ap_holds_all
     WHERE invoice_id = p_invoice_id
       AND release_lookup_code IS NULL;

    FOR l IN (
      SELECT il.line_number,
             il.quantity_invoiced,
             il.unit_price,
             pl.unit_price AS po_price,
             pl.quantity   AS po_qty,
             (SELECT NVL(SUM(CASE rt.transaction_type
                               WHEN 'RECEIVE'          THEN rt.quantity
                               WHEN 'RETURN TO VENDOR' THEN -rt.quantity
                               ELSE 0 END), 0)
                FROM rcv_transactions rt
               WHERE rt.po_line_id = il.po_line_id) AS qty_received
        FROM ap_invoice_lines_all il
        JOIN po_lines_all pl ON pl.po_line_id = il.po_line_id
       WHERE il.invoice_id = p_invoice_id
       ORDER BY il.line_number)
    LOOP
      IF l.quantity_invoiced > l.po_qty THEN
        place_hold(p_invoice_id, l.line_number, 'QTY ORD',
                   'Billed ' || l.quantity_invoiced || ' > ordered ' || l.po_qty);
      END IF;

      IF l.quantity_invoiced > l.qty_received THEN
        place_hold(p_invoice_id, l.line_number, 'QTY REC',
                   'Billed ' || l.quantity_invoiced || ' > received ' || l.qty_received);
      END IF;

      IF l.unit_price > l.po_price * (1 + c_price_tolerance) THEN
        place_hold(p_invoice_id, l.line_number, 'PRICE',
                   'Unit price ' || l.unit_price || ' exceeds PO price ' || l.po_price || ' + tolerance');
      END IF;
    END LOOP;

    l_holds := open_hold_count(p_invoice_id);
    UPDATE ap_invoices_all
       SET validation_status = CASE WHEN l_holds > 0
                                    THEN 'NEEDS REVALIDATION'
                                    ELSE 'VALIDATED' END
     WHERE invoice_id = p_invoice_id;
  END validate_invoice;

  PROCEDURE validate_all IS
  BEGIN
    FOR i IN (SELECT invoice_id FROM ap_invoices_all
               WHERE validation_status <> 'VALIDATED'
               ORDER BY invoice_id) LOOP
      validate_invoice(i.invoice_id);
    END LOOP;
    COMMIT;
  END validate_all;

END xx_ap_match_pkg;
/
