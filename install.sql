-- Run as the application schema owner:
--   sqlplus ebslab/<password>@//localhost:1521/FREEPDB1 @install.sql
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
SET ECHO OFF FEEDBACK ON
ALTER SESSION SET PLSQL_WARNINGS = 'ENABLE:SEVERE';

PROMPT === Schema ===
@@sql/01_schema.sql
PROMPT === Seed data ===
@@sql/02_seed.sql
PROMPT === PL/SQL packages ===
@@plsql/xx_ap_import_pkg.sql
SHOW ERRORS
@@plsql/xx_ap_match_pkg.sql
SHOW ERRORS
@@plsql/xx_ap_approval_pkg.sql
SHOW ERRORS
@@plsql/xx_gl_pkg.sql
SHOW ERRORS
@@plsql/xx_hxc_pkg.sql
SHOW ERRORS
PROMPT === Reporting views ===
@@sql/03_reporting_views.sql

-- Fail the build if anything compiled with errors
DECLARE
  l_bad NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_bad FROM user_objects WHERE status = 'INVALID';
  IF l_bad > 0 THEN
    RAISE_APPLICATION_ERROR(-20900, l_bad || ' invalid object(s) after install');
  END IF;
END;
/
PROMPT === Install complete ===
