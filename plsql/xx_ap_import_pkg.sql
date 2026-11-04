-- XX_AP_IMPORT_PKG
-- Mirrors the job of the Payables Open Interface Import concurrent program:
-- validate staged invoices, reject bad rows with a reason code, and create
-- AP_INVOICES_ALL / AP_INVOICE_LINES_ALL for good rows.

CREATE OR REPLACE PACKAGE xx_ap_import_pkg AS
  PROCEDURE run_import (x_imported OUT NUMBER, x_rejected OUT NUMBER);
END xx_ap_import_pkg;
/

CREATE OR REPLACE PACKAGE BODY xx_ap_import_pkg AS

  PROCEDURE reject (p_invoice_id NUMBER, p_code VARCHAR2, p_message VARCHAR2) IS
  BEGIN
    INSERT INTO ap_interface_rejections (parent_id, reject_lookup_code, message)
    VALUES (p_invoice_id, p_code, p_message);
  END reject;

  PROCEDURE run_import (x_imported OUT NUMBER, x_rejected OUT NUMBER) IS
    l_enabled      ap_suppliers.enabled_flag%TYPE;
    l_line_total   NUMBER;
    l_dup_count    NUMBER;
    l_bad_lines    NUMBER;
    l_po_header_id po_headers_all.po_header_id%TYPE;
    l_po_vendor_id po_headers_all.vendor_id%TYPE;
    l_ok           BOOLEAN;
  BEGIN
    x_imported := 0;
    x_rejected := 0;

    FOR r IN (SELECT * FROM ap_invoices_interface
               WHERE status = 'NEW'
               ORDER BY invoice_id) LOOP
      l_ok := TRUE;
      l_po_header_id := NULL;

      -- 1. Required header fields
      IF r.invoice_num IS NULL OR r.invoice_date IS NULL OR r.invoice_amount IS NULL THEN
        reject(r.invoice_id, 'MISSING REQUIRED FIELD', 'Invoice number, date and amount are required');
        l_ok := FALSE;
      END IF;

      -- 2. Supplier exists and is active
      BEGIN
        SELECT enabled_flag INTO l_enabled
          FROM ap_suppliers
         WHERE vendor_id = r.vendor_id;
        IF l_enabled <> 'Y' THEN
          reject(r.invoice_id, 'INACTIVE SUPPLIER', 'Supplier ' || r.vendor_id || ' is inactive');
          l_ok := FALSE;
        END IF;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          reject(r.invoice_id, 'INVALID SUPPLIER', 'Supplier ' || r.vendor_id || ' not found');
          l_ok := FALSE;
      END;

      -- 3. Duplicate invoice number for the same supplier
      SELECT COUNT(*) INTO l_dup_count
        FROM ap_invoices_all
       WHERE vendor_id = r.vendor_id
         AND invoice_num = r.invoice_num;
      IF l_dup_count > 0 THEN
        reject(r.invoice_id, 'DUPLICATE INVOICE', 'Invoice ' || r.invoice_num || ' already exists for this supplier');
        l_ok := FALSE;
      END IF;

      -- 4. Header amount must equal the sum of the lines
      SELECT NVL(SUM(amount), 0) INTO l_line_total
        FROM ap_invoice_lines_interface
       WHERE invoice_id = r.invoice_id;
      IF l_line_total <> NVL(r.invoice_amount, -1) THEN
        reject(r.invoice_id, 'INVOICE AMOUNT MISMATCH',
               'Header ' || r.invoice_amount || ' <> lines ' || l_line_total);
        l_ok := FALSE;
      END IF;

      -- 5. PO exists, belongs to the supplier, and every PO line referenced exists
      IF r.po_number IS NOT NULL THEN
        BEGIN
          SELECT po_header_id, vendor_id INTO l_po_header_id, l_po_vendor_id
            FROM po_headers_all
           WHERE segment1 = r.po_number;
          IF l_po_vendor_id <> r.vendor_id THEN
            reject(r.invoice_id, 'PO SUPPLIER MISMATCH', 'PO ' || r.po_number || ' belongs to another supplier');
            l_ok := FALSE;
          END IF;

          SELECT COUNT(*) INTO l_bad_lines
            FROM ap_invoice_lines_interface li
           WHERE li.invoice_id = r.invoice_id
             AND NOT EXISTS (SELECT 1 FROM po_lines_all pl
                              WHERE pl.po_header_id = l_po_header_id
                                AND pl.line_num = li.po_line_num);
          IF l_bad_lines > 0 THEN
            reject(r.invoice_id, 'INVALID PO LINE', l_bad_lines || ' line(s) reference a PO line that does not exist');
            l_ok := FALSE;
          END IF;
        EXCEPTION
          WHEN NO_DATA_FOUND THEN
            reject(r.invoice_id, 'INVALID PO NUM', 'PO ' || r.po_number || ' not found');
            l_ok := FALSE;
        END;
      END IF;

      IF l_ok THEN
        INSERT INTO ap_invoices_all (invoice_id, invoice_num, vendor_id, invoice_date,
                                     invoice_amount, po_header_id)
        VALUES (r.invoice_id, r.invoice_num, r.vendor_id, r.invoice_date,
                r.invoice_amount, l_po_header_id);

        INSERT INTO ap_invoice_lines_all (invoice_id, line_number, po_line_id, quantity_invoiced,
                                          unit_price, amount, dist_code_combination_id)
        SELECT li.invoice_id, li.line_number, pl.po_line_id, li.quantity_invoiced,
               li.unit_price, li.amount, pl.charge_account_id
          FROM ap_invoice_lines_interface li
          LEFT JOIN po_lines_all pl
            ON pl.po_header_id = l_po_header_id
           AND pl.line_num     = li.po_line_num
         WHERE li.invoice_id = r.invoice_id;

        UPDATE ap_invoices_interface SET status = 'PROCESSED' WHERE invoice_id = r.invoice_id;
        x_imported := x_imported + 1;
      ELSE
        UPDATE ap_invoices_interface SET status = 'REJECTED' WHERE invoice_id = r.invoice_id;
        x_rejected := x_rejected + 1;
      END IF;
    END LOOP;

    COMMIT;
  END run_import;

END xx_ap_import_pkg;
/
