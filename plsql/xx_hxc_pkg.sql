-- XX_HXC_PKG
-- Timecard validation rules (the kind normally added to Oracle Time and Labor
-- through time entry rules / custom validation) and an overtime calculation.

CREATE OR REPLACE PACKAGE xx_hxc_pkg AS
  c_weekly_ot_threshold CONSTANT NUMBER := 40;

  PROCEDURE validate_timecard (p_timecard_id NUMBER);
  PROCEDURE validate_all;
  FUNCTION  overtime_hours    (p_timecard_id NUMBER) RETURN NUMBER;
END xx_hxc_pkg;
/

CREATE OR REPLACE PACKAGE BODY xx_hxc_pkg AS

  PROCEDURE log_error (p_timecard_id NUMBER, p_code VARCHAR2, p_message VARCHAR2) IS
  BEGIN
    INSERT INTO hxc_validation_errors (timecard_id, error_code, message)
    VALUES (p_timecard_id, p_code, p_message);
  END log_error;

  PROCEDURE validate_timecard (p_timecard_id NUMBER) IS
    l_errors NUMBER;
  BEGIN
    DELETE FROM hxc_validation_errors WHERE timecard_id = p_timecard_id;

    -- No more than 24 hours on any single day
    FOR d IN (SELECT work_date, SUM(hours) AS total
                FROM hxc_time_entries
               WHERE timecard_id = p_timecard_id
               GROUP BY work_date
              HAVING SUM(hours) > 24) LOOP
      log_error(p_timecard_id, 'HOURS_EXCEED_24',
                TO_CHAR(d.work_date, 'YYYY-MM-DD') || ' has ' || d.total || ' hours');
    END LOOP;

    -- No negative hours
    FOR n IN (SELECT work_date FROM hxc_time_entries
               WHERE timecard_id = p_timecard_id AND hours < 0) LOOP
      log_error(p_timecard_id, 'NEGATIVE_HOURS', TO_CHAR(n.work_date, 'YYYY-MM-DD'));
    END LOOP;

    -- Every entry must fall inside the timecard period
    FOR o IN (SELECT e.work_date
                FROM hxc_time_entries e
                JOIN hxc_timecards t ON t.timecard_id = e.timecard_id
               WHERE e.timecard_id = p_timecard_id
                 AND e.work_date NOT BETWEEN t.period_start AND t.period_end) LOOP
      log_error(p_timecard_id, 'DATE_OUT_OF_PERIOD', TO_CHAR(o.work_date, 'YYYY-MM-DD') || ' is outside the period');
    END LOOP;

    SELECT COUNT(*) INTO l_errors FROM hxc_validation_errors WHERE timecard_id = p_timecard_id;

    UPDATE hxc_timecards
       SET approval_status = CASE WHEN l_errors > 0 THEN 'ERROR' ELSE 'VALIDATED' END
     WHERE timecard_id = p_timecard_id;
  END validate_timecard;

  PROCEDURE validate_all IS
  BEGIN
    FOR t IN (SELECT timecard_id FROM hxc_timecards WHERE approval_status = 'SUBMITTED') LOOP
      validate_timecard(t.timecard_id);
    END LOOP;
    COMMIT;
  END validate_all;

  -- FLSA-style weekly overtime: hours over 40 for non-exempt employees
  FUNCTION overtime_hours (p_timecard_id NUMBER) RETURN NUMBER IS
    l_total  NUMBER;
    l_exempt CHAR(1);
  BEGIN
    SELECT NVL(SUM(e.hours), 0), MAX(a.flsa_exempt)
      INTO l_total, l_exempt
      FROM hxc_timecards t
      JOIN per_all_assignments_f a
        ON a.person_id = t.person_id
       AND t.period_start BETWEEN a.effective_start_date AND a.effective_end_date
      LEFT JOIN hxc_time_entries e ON e.timecard_id = t.timecard_id
     WHERE t.timecard_id = p_timecard_id;

    IF l_exempt = 'Y' THEN
      RETURN 0;
    END IF;
    RETURN GREATEST(l_total - c_weekly_ot_threshold, 0);
  END overtime_hours;

END xx_hxc_pkg;
/
