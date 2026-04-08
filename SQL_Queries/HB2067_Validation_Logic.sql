### `SQL_Queries/HB2067_Validation_Logic.sql`

This file contains the queries for creating validation views, the self-contained script for populating the exception log, and the CTAS query for correcting data, aligning with the remediation strategy for the BigQuery free tier.

```sql
-- UPPER-CASE DESCRIPTION: SQL_QUERIES_FOR_REASON_CODE_VALIDATION_AND_CONCATENATION
-- Project ID: driiiportfolio

-- QUERY 1: IDENTIFY NON-ALPHABETICAL REASON CODES
-- The TDI requires codes to be in alphabetical order (e.g., 'FK' not 'KF')
CREATE OR REPLACE VIEW `driiiportfolio.tfb_underwriting.v_non_alphabetical_reasons` AS
WITH exploded_codes AS (
    SELECT
        RECORD_ID,
        REASON_CODES,
        ch
    FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions`,
    UNNEST(SPLIT(REASON_CODES, '')) AS ch
),
reconstructed AS (
    SELECT
        RECORD_ID,
        STRING_AGG(ch, '' ORDER BY ch) AS sorted_codes
    FROM exploded_codes
    GROUP BY RECORD_ID
)
SELECT
    r.RECORD_ID,
    r.REASON_CODES AS original_codes,
    s.sorted_codes,
    'REASON_CODE_ORDER_MISMATCH' AS dq_error
FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions` r
JOIN reconstructed s ON r.RECORD_ID = s.RECORD_ID
WHERE r.REASON_CODES != s.sorted_codes;

-- QUERY 2: VALIDATE THE 60-DAY INDICATOR LOGIC
-- Ensures the Boolean indicator matches the difference between dates
CREATE OR REPLACE VIEW `driiiportfolio.tfb_underwriting.v_indicator_60d_mismatch` AS
SELECT
    RECORD_ID,
    NOTIFICATION_DATE,
    EFFECTIVE_DATE,
    INDICATOR_60D,
    DATE_DIFF(EFFECTIVE_DATE, NOTIFICATION_DATE, DAY) as actual_diff,
    'INDICATOR_60D_MISMATCH' AS dq_error
FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions`
WHERE (DATE_DIFF(EFFECTIVE_DATE, NOTIFICATION_DATE, DAY) >= 60 AND INDICATOR_60D = 0)
   OR (DATE_DIFF(EFFECTIVE_DATE, NOTIFICATION_DATE, DAY) < 60 AND INDICATOR_60D = 1);

-- QUERY 3: THIRD-PARTY DATA CONSISTENCY CHECK [16]
-- If Aerial Imagery is True, Third Party Indicator must be 'Y'
CREATE OR REPLACE VIEW `driiiportfolio.tfb_underwriting.v_aerial_indicator_mismatch` AS
SELECT
    RECORD_ID,
    THIRD_PARTY_IND,
    AERIAL_IMAGERY,
    'AERIAL_WITHOUT_THIRD_PARTY_FLAG' AS dq_error
FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions`
WHERE AERIAL_IMAGERY = 1 AND THIRD_PARTY_IND != 'Y';


-- Self-contained script for populating the dq_exception_log table
CREATE OR REPLACE TABLE `driiiportfolio.tfb_underwriting.dq_exception_log` AS
-- 1. Log non-alphabetical reason codes (Self-contained logic)
SELECT
    r.RECORD_ID,
    'REASON_CODE_ORDER_MISMATCH' as CHECK_NAME,
    'HIGH' as SEVERITY,
    'Reason codes not alphabetical: ' || r.REASON_CODES as ERROR_DESCRIPTION,
    CURRENT_TIMESTAMP() as LOG_TIMESTAMP
FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions` r
JOIN (
    SELECT
        RECORD_ID,
        STRING_AGG(ch, '' ORDER BY ch) AS sorted_codes
    FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions`,
    UNNEST(SPLIT(REASON_CODES, '')) AS ch
    GROUP BY RECORD_ID
) s ON r.RECORD_ID = s.RECORD_ID
WHERE r.REASON_CODES != s.sorted_codes

UNION ALL

-- 2. Log 60-day indicator mismatches
SELECT
    RECORD_ID,
    'INDICATOR_60D_MISMATCH' as CHECK_NAME,
    'HIGH' as SEVERITY,
    '60-day indicator mismatch: NOTIFICATION_DATE=' || CAST(NOTIFICATION_DATE AS STRING) || ', EFFECTIVE_DATE=' || CAST(EFFECTIVE_DATE AS STRING),
    CURRENT_TIMESTAMP() as LOG_TIMESTAMP
FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions`
WHERE (DATE_DIFF(EFFECTIVE_DATE, NOTIFICATION_DATE, DAY) >= 60 AND INDICATOR_60D = 0)
   OR (DATE_DIFF(EFFECTIVE_DATE, NOTIFICATION_DATE, DAY) < 60 AND INDICATOR_60D = 1)

UNION ALL

-- 3. Log aerial imagery consistency mismatches
SELECT
    RECORD_ID,
    'AERIAL_WITHOUT_THIRD_PARTY_FLAG' as CHECK_NAME,
    'HIGH' as SEVERITY,
    'Aerial imagery used (AERIAL_IMAGERY=1) but THIRD_PARTY_IND is not Y',
    CURRENT_TIMESTAMP() as LOG_TIMESTAMP
FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions`
WHERE AERIAL_IMAGERY = 1 AND THIRD_PARTY_IND != 'Y'

UNION ALL

-- 4. Log missing ZIP codes
SELECT
    RECORD_ID,
    'MISSING_ZIP_CODE' as CHECK_NAME,
    'HIGH' as SEVERITY,
    'ZIP_CODE is NULL',
    CURRENT_TIMESTAMP() as LOG_TIMESTAMP
FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions`
WHERE ZIP_CODE IS NULL

UNION ALL

-- 5. Log date inconsistencies
SELECT
    RECORD_ID,
    'DATE_INCONSISTENCY' as CHECK_NAME,
    'HIGH' as SEVERITY,
    'EFFECTIVE_DATE is before NOTIFICATION_DATE',
    CURRENT_TIMESTAMP() as LOG_TIMESTAMP
FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions`
WHERE EFFECTIVE_DATE < NOTIFICATION_DATE;


-- Data Correction via CTAS (Create Table As Select)
CREATE OR REPLACE TABLE `driiiportfolio.tfb_underwriting.raw_adverse_actions_compliant` AS
WITH base_corrections AS (
    SELECT
        RECORD_ID,
        POLICY_NUMBER,
        NOTIFICATION_DATE,
        ACTION_TYPE,
        POLICY_TYPE,
        REASON_SOURCE,
        -- 1. Fill Missing ZIP Codes with Default '76701'
        COALESCE(ZIP_CODE, '76701') AS ZIP_CODE,
        -- 2. Correct Date Inconsistency (Effective = Notification + 15 if earlier)
        CASE 
            WHEN EFFECTIVE_DATE < NOTIFICATION_DATE THEN DATE_ADD(NOTIFICATION_DATE, INTERVAL 15 DAY)
            ELSE EFFECTIVE_DATE
        END AS EFFECTIVE_DATE,
        -- 3. Standardize Reason Codes to Alphabetical Order
        (SELECT STRING_AGG(ch, '' ORDER BY ch) FROM UNNEST(SPLIT(REASON_CODES, '')) AS ch) AS REASON_CODES,
        -- 4. Correct Aerial Imagery Flags (Set to 'Y' if imagery is used)
        CASE 
            WHEN AERIAL_IMAGERY = 1 AND THIRD_PARTY_IND != 'Y' THEN 'Y'
            ELSE THIRD_PARTY_IND
        END AS THIRD_PARTY_IND,
        AERIAL_IMAGERY
    FROM
        `driiiportfolio.tfb_underwriting.raw_adverse_actions`
)
SELECT
    RECORD_ID,
    POLICY_NUMBER,
    NOTIFICATION_DATE,
    ACTION_TYPE,
    POLICY_TYPE,
    REASON_SOURCE,
    ZIP_CODE,
    EFFECTIVE_DATE,
    REASON_CODES,
    THIRD_PARTY_IND,
    AERIAL_IMAGERY,
    -- 5. Recalculate 60-day Indicator based on corrected dates
    CASE
        WHEN DATE_DIFF(EFFECTIVE_DATE, NOTIFICATION_DATE, DAY) >= 60 THEN 1
        ELSE 0
    END AS INDICATOR_60D
FROM
    base_corrections;
```
