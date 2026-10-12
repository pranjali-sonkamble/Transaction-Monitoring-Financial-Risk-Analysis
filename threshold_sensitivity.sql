-- SAML-D threshold sensitivity analysis (SQLite)
-- Read-only: this script does not modify risk_rules.sql or derived tables.
-- Run from AML_Project:
--   "C:\Program Files\SQLite ODBC Driver for Win64\sqlite3.exe" -header -column database\aml_monitoring.db < sql\threshold_sensitivity.sql
--
-- The current score threshold (80+) is equivalent to:
-- max transaction amount > very_high_amount OR
-- (max transaction amount > high_amount AND transaction_count > activity_count).
-- Predictions are account-level; performance below is measured per transaction
-- row by applying each sender's account flag to each of its transactions.
-- This is NOT account-level precision/recall.
-- Label values expected: 1/0, true/false, yes/no.

WITH
params(high_amount, very_high_amount, activity_count) AS (
    VALUES
        (100000.0, 250000.0, 300),
        (100000.0, 250000.0, 100),
        (100000.0, 250000.0, 500),
        (100000.0, 500000.0, 300),
        (100000.0, 500000.0, 100),
        (100000.0, 500000.0, 500),
        (50000.0, 250000.0, 300),
        (50000.0, 250000.0, 100),
        (50000.0, 250000.0, 500)
),
account_metrics AS (
    SELECT
        Sender_account AS account_id,
        COUNT(*) AS transaction_count,
        MAX(Amount) AS max_transaction_amount,
        SUM(CASE
            WHEN lower(trim(CAST(Is_laundering AS TEXT))) IN ('1','true','yes')
            THEN 1 ELSE 0 END) AS positive_label_rows,
        SUM(CASE
            WHEN lower(trim(CAST(Is_laundering AS TEXT))) IN ('0','false','no')
            THEN 1 ELSE 0 END) AS negative_label_rows
    FROM saml_d_raw
    GROUP BY Sender_account
),
predictions AS (
    SELECT
        p.high_amount,
        p.very_high_amount,
        p.activity_count,
        a.account_id,
        a.positive_label_rows,
        a.negative_label_rows,
        CASE
            WHEN a.max_transaction_amount > p.very_high_amount THEN 1
            WHEN a.max_transaction_amount > p.high_amount
                 AND a.transaction_count > p.activity_count THEN 1
            ELSE 0
        END AS flagged
    FROM params AS p
    CROSS JOIN account_metrics AS a
),
summary AS (
    SELECT
        high_amount,
        very_high_amount,
        activity_count,
        COUNT(*) AS distinct_sender_accounts,
        SUM(flagged) AS flagged_sender_accounts,
        SUM(CASE WHEN flagged = 1 THEN positive_label_rows ELSE 0 END) AS tp,
        SUM(CASE WHEN flagged = 1 THEN negative_label_rows ELSE 0 END) AS fp,
        SUM(CASE WHEN flagged = 0 THEN positive_label_rows ELSE 0 END) AS fn,
        SUM(CASE WHEN flagged = 0 THEN negative_label_rows ELSE 0 END) AS tn
    FROM predictions
    GROUP BY high_amount, very_high_amount, activity_count
)
SELECT
    high_amount,
    very_high_amount,
    activity_count,
    flagged_sender_accounts,
    ROUND(100.0 * flagged_sender_accounts / NULLIF(distinct_sender_accounts, 0), 2) AS pct_sender_accounts_flagged,
    tp AS true_positive_rows,
    fp AS false_positive_rows,
    fn AS false_negative_rows,
    tn AS true_negative_rows,
    ROUND(100.0 * tp / NULLIF(tp + fp, 0), 4) AS precision_pct,
    ROUND(100.0 * tp / NULLIF(tp + fn, 0), 4) AS recall_pct,
    ROUND(100.0 * tn / NULLIF(tn + fp, 0), 4) AS specificity_pct
FROM summary
ORDER BY precision_pct DESC, recall_pct DESC;
