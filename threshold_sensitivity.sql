-- SAML-D threshold sensitivity analysis (SQLite)
-- Run after loading saml_d_raw. This script is READ-ONLY: it does not change
-- risk_rules.sql, derived tables, or the Power BI model.
-- Run from AML_Project:
--   "C:\Program Files\SQLite ODBC Driver for Win64\sqlite3.exe" -header -column database\aml_monitoring.db < sql\threshold_sensitivity.sql
--
-- Account flag rule mirrors the current additive scoring threshold of 80+:
-- flagged if max transaction amount > very_high_amount OR
-- (max transaction amount > high_amount AND transaction_count > activity_count).
-- This is an account-level flag evaluated at transaction-row level against
-- Is_laundering. Account-level precision/recall would require an account-level
-- ground-truth definition, which is not inferred here.
--
-- Edit candidate values below only if Amount uses a different currency/scale.
-- Label encoding expected: 1/0, true/false, yes/no.

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
        MAX(Amount) AS max_transaction_amount
    FROM saml_d_raw
    GROUP BY Sender_account
),
account_labels AS (
    SELECT
        Sender_account AS account_id,
        MAX(
            CASE
                WHEN lower(trim(CAST(Is_laundering AS TEXT))) IN ('1', 'true', 'yes')
                THEN 1 ELSE 0
            END
        ) AS has_positive_label
    FROM saml_d_raw
    GROUP BY Sender_account
),
predictions AS (
    SELECT
        p.high_amount,
        p.very_high_amount,
        p.activity_count,
        a.account_id,
        CASE
            WHEN a.max_transaction_amount > p.very_high_amount THEN 1
            WHEN a.max_transaction_amount > p.high_amount
                 AND a.transaction_count > p.activity_count THEN 1
            ELSE 0
        END AS flagged
    FROM params AS p
    CROSS JOIN account_metrics AS a
),
account_summary AS (
    SELECT
        high_amount,
        very_high_amount,
        activity_count,
        COUNT(*) AS distinct_sender_accounts,
        SUM(flagged) AS flagged_sender_accounts,
        ROUND(100.0 * SUM(flagged) / NULLIF(COUNT(*), 0), 2) AS pct_sender_accounts_flagged
    FROM predictions
    GROUP BY high_amount, very_high_amount, activity_count
),
transaction_evaluation AS (
    SELECT
        p.high_amount,
        p.very_high_amount,
        p.activity_count,
        SUM(CASE WHEN p.flagged = 1 AND
            lower(trim(CAST(t.Is_laundering AS TEXT))) IN ('1','true','yes') THEN 1 ELSE 0 END) AS tp,
        SUM(CASE WHEN p.flagged = 1 AND
            lower(trim(CAST(t.Is_laundering AS TEXT))) IN ('0','false','no') THEN 1 ELSE 0 END) AS fp,
        SUM(CASE WHEN p.flagged = 0 AND
            lower(trim(CAST(t.Is_laundering AS TEXT))) IN ('1','true','yes') THEN 1 ELSE 0 END) AS fn,
        SUM(CASE WHEN p.flagged = 0 AND
            lower(trim(CAST(t.Is_laundering AS TEXT))) IN ('0','false','no') THEN 1 ELSE 0 END) AS tn
    FROM saml_d_raw AS t
    JOIN predictions AS p ON p.account_id = t.Sender_account
    GROUP BY p.high_amount, p.very_high_amount, p.activity_count
)
SELECT
    e.high_amount,
    e.very_high_amount,
    e.activity_count,
    a.flagged_sender_accounts,
    a.pct_sender_accounts_flagged,
    e.tp AS true_positive_rows,
    e.fp AS false_positive_rows,
    e.fn AS false_negative_rows,
    e.tn AS true_negative_rows,
    ROUND(100.0 * e.tp / NULLIF(e.tp + e.fp, 0), 4) AS precision_pct,
    ROUND(100.0 * e.tp / NULLIF(e.tp + e.fn, 0), 4) AS recall_pct,
    ROUND(100.0 * e.tn / NULLIF(e.tn + e.fp, 0), 4) AS specificity_pct
FROM transaction_evaluation AS e
JOIN account_summary AS a
  ON a.high_amount = e.high_amount
 AND a.very_high_amount = e.very_high_amount
 AND a.activity_count = e.activity_count
ORDER BY precision_pct DESC, recall_pct DESC;
