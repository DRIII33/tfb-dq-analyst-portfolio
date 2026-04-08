### `SQL_Queries/TICO_Reporting_Audit.sql`

This file includes the queries for auditing compliance, both for the initial raw data and the final compliant table, as well as the generation of the Section G submission table.

```sql
-- UPPER-CASE DESCRIPTION: TICO_SUBMISSION_AUDIT_AND_ERROR_PROFILING
-- Project ID: driiiportfolio

-- CALCULATE OVERALL DATA QUALITY COMPLIANCE SCORE (initial raw data profiling)
WITH dq_summary AS (
    SELECT
        COUNT(*) as total_records,
        SUM(CASE WHEN ZIP_CODE IS NULL THEN 1 ELSE 0 END) as missing_zips,
        SUM(CASE WHEN EFFECTIVE_DATE < NOTIFICATION_DATE THEN 1 ELSE 0 END) as date_errors,
        (SELECT COUNT(*) FROM `driiiportfolio.tfb_underwriting.v_non_alphabetical_reasons`) as sorting_errors,
        (SELECT COUNT(*) FROM `driiiportfolio.tfb_underwriting.v_indicator_60d_mismatch`) as logic_errors,
        (SELECT COUNT(*) FROM `driiiportfolio.tfb_underwriting.v_aerial_indicator_mismatch`) as aerial_indicator_errors
    FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions`
)
SELECT
    total_records,
    missing_zips,
    date_errors,
    sorting_errors,
    logic_errors,
    aerial_indicator_errors,
    (missing_zips + date_errors + sorting_errors + logic_errors + aerial_indicator_errors) as total_faults,
    ROUND(((missing_zips + date_errors + sorting_errors + logic_errors + aerial_indicator_errors) / total_records) * 100, 2) as fault_rate_pct,
    CASE
        WHEN ((missing_zips + date_errors + sorting_errors + logic_errors + aerial_indicator_errors) / total_records) > 0.01
        THEN 'REJECTED - EXCEEDS 1% TOLERANCE'
        ELSE 'ACCEPTED'
    END as tico_status
FROM dq_summary;

-- Re-evaluate overall data quality compliance score on the new compliant table
WITH dq_summary AS (
    SELECT
        COUNT(*) as total_records,
        SUM(CASE WHEN ZIP_CODE IS NULL THEN 1 ELSE 0 END) as missing_zips,
        SUM(CASE WHEN EFFECTIVE_DATE < NOTIFICATION_DATE THEN 1 ELSE 0 END) as date_errors,
        (SELECT COUNT(r.RECORD_ID) FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions_compliant` r JOIN (SELECT RECORD_ID, STRING_AGG(ch, '' ORDER BY ch) AS sorted_codes FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions_compliant`, UNNEST(SPLIT(REASON_CODES, '')) AS ch GROUP BY RECORD_ID) s ON r.RECORD_ID = s.RECORD_ID WHERE r.REASON_CODES != s.sorted_codes) as sorting_errors,
        (SELECT COUNT(*) FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions_compliant` WHERE (DATE_DIFF(EFFECTIVE_DATE, NOTIFICATION_DATE, DAY) >= 60 AND INDICATOR_60D = 0) OR (DATE_DIFF(EFFECTIVE_DATE, NOTIFICATION_DATE, DAY) < 60 AND INDICATOR_60D = 1)) as logic_errors,
        (SELECT COUNT(*) FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions_compliant` WHERE AERIAL_IMAGERY = 1 AND THIRD_PARTY_IND != 'Y') as aerial_indicator_errors
    FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions_compliant`
)
SELECT
    total_records,
    missing_zips,
    date_errors,
    sorting_errors,
    logic_errors,
    aerial_indicator_errors,
    (missing_zips + date_errors + sorting_errors + logic_errors + aerial_indicator_errors) as total_faults,
    ROUND(((missing_zips + date_errors + sorting_errors + logic_errors + aerial_indicator_errors) / total_records) * 100, 2) as fault_rate_pct,
    CASE
        WHEN ((missing_zips + date_errors + sorting_errors + logic_errors + aerial_indicator_errors) / total_records) > 0.01
        THEN 'REJECTED - EXCEEDS 1% TOLERANCE'
        ELSE 'ACCEPTED'
    END as tico_status
FROM dq_summary;

-- GENERATE SECTION G: AGGREGATED ACTUALIZED COUNTS BY ZIP [15, 20, 21]
CREATE OR REPLACE TABLE `driiiportfolio.tfb_underwriting.section_g_submission_april_2026` AS
SELECT
    ZIP_CODE,
    ACTION_TYPE,
    COUNT(DISTINCT POLICY_NUMBER) as actualized_policy_count
FROM `driiiportfolio.tfb_underwriting.raw_adverse_actions`
WHERE ZIP_CODE IS NOT NULL
  AND EFFECTIVE_DATE BETWEEN '2026-04-01' AND '2026-04-30'
GROUP BY 1, 2
ORDER BY ZIP_CODE ASC;
```
