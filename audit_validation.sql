-- SAML-D local audit queries (SQLite)
-- Run AFTER risk_rules.sql, against a working copy containing saml_d_raw.
-- Example:
--   sqlite3 -header -column saml_d.db < audit_validation.sql
-- These queries calculate metrics locally; they do not export raw transactions.
--
-- Interpretation:
-- * "Flagged" means the sender account's heuristic risk_level is High or Severe.
-- * Is_laundering is used ONLY as an evaluation label, never by the risk rules.
-- * Precision/recall below are transaction-row metrics for this account-level
--   flag applied to each transaction. They are not account-level metrics.
-- * Label values recognized as positive: 1, true, yes; negative: 0, false, no.
--   Review the label-distribution query if your source encodes labels differently.

.headers on
.mode column

-- 1) Dataset size, distinct senders, null labels, and source date range.
SELECT
    COUNT(*) AS transaction_rows,
    COUNT(DISTINCT Sender_account) AS distinct_sender_accounts,
    SUM(CASE WHEN Is_laundering IS NULL THEN 1 ELSE 0 END) AS null_label_rows,
    MIN(Date) AS min_source_date,
    MAX(Date) AS max_source_date
FROM saml_d_raw;

-- 2) Inspect source label encoding before interpreting performance metrics.
SELECT
    lower(trim(CAST(Is_laundering AS TEXT))) AS label_value,
    COUNT(*) AS rows
FROM saml_d_raw
GROUP BY lower(trim(CAST(Is_laundering AS TEXT)))
ORDER BY rows DESC;

-- 3) Number/share of distinct sender accounts in High or Severe risk tiers.
WITH sender_totals AS (
    SELECT COUNT(DISTINCT Sender_account) AS total_senders
    FROM saml_d_raw
),
flagged_senders AS (
    SELECT COUNT(DISTINCT Sender_account) AS flagged_senders
    FROM customer_risk_categorized
    WHERE risk_level IN ('High', 'Severe')
)
SELECT
    total_senders,
    flagged_senders,
    ROUND(100.0 * flagged_senders / NULLIF(total_senders, 0), 2) AS pct_sender_accounts_flagged
FROM sender_totals CROSS JOIN flagged_senders;

-- 4) Transaction-row confusion matrix. The account's risk tier is mapped to
-- each of its transactions, then compared with the source ground-truth label.
WITH labeled AS (
    SELECT
        CASE WHEN r.risk_level IN ('High', 'Severe') THEN 1 ELSE 0 END AS predicted_flag,
        CASE
            WHEN lower(trim(CAST(t.Is_laundering AS TEXT))) IN ('1', 'true', 'yes') THEN 1
            WHEN lower(trim(CAST(t.Is_laundering AS TEXT))) IN ('0', 'false', 'no') THEN 0
            ELSE NULL
        END AS actual_label
    FROM saml_d_raw AS t
    LEFT JOIN customer_risk_categorized AS r
      ON r.account_id = t.Sender_account
)
SELECT
    COUNT(*) AS all_transaction_rows,
    SUM(CASE WHEN actual_label IS NOT NULL THEN 1 ELSE 0 END) AS rows_with_recognized_label,
    SUM(CASE WHEN actual_label IS NULL THEN 1 ELSE 0 END) AS rows_with_unrecognized_or_missing_label,
    SUM(CASE WHEN predicted_flag = 1 AND actual_label = 1 THEN 1 ELSE 0 END) AS true_positive_rows,
    SUM(CASE WHEN predicted_flag = 1 AND actual_label = 0 THEN 1 ELSE 0 END) AS false_positive_rows,
    SUM(CASE WHEN predicted_flag = 0 AND actual_label = 1 THEN 1 ELSE 0 END) AS false_negative_rows,
    SUM(CASE WHEN predicted_flag = 0 AND actual_label = 0 THEN 1 ELSE 0 END) AS true_negative_rows,
    ROUND(
      100.0 * SUM(CASE WHEN predicted_flag = 1 AND actual_label = 1 THEN 1 ELSE 0 END)
      / NULLIF(SUM(CASE WHEN predicted_flag = 1 AND actual_label IS NOT NULL THEN 1 ELSE 0 END), 0),
      4
    ) AS precision_pct,
    ROUND(
      100.0 * SUM(CASE WHEN predicted_flag = 1 AND actual_label = 1 THEN 1 ELSE 0 END)
      / NULLIF(SUM(CASE WHEN actual_label = 1 THEN 1 ELSE 0 END), 0),
      4
    ) AS recall_pct,
    ROUND(
      100.0 * SUM(CASE WHEN predicted_flag = 0 AND actual_label = 0 THEN 1 ELSE 0 END)
      / NULLIF(SUM(CASE WHEN actual_label = 0 THEN 1 ELSE 0 END), 0),
      4
    ) AS specificity_pct
FROM labeled;

-- 5) Confirm the derived dashboard table sizes and account risk distribution.
SELECT 'customer_risk_categorized' AS output_table, COUNT(*) AS rows
FROM customer_risk_categorized
UNION ALL
SELECT 'dashboard_cases', COUNT(*) FROM dashboard_cases
UNION ALL
SELECT 'dashboard_transactions', COUNT(*) FROM dashboard_transactions;

SELECT risk_level, COUNT(*) AS sender_accounts
FROM customer_risk_categorized
GROUP BY risk_level
ORDER BY CASE risk_level
    WHEN 'Severe' THEN 1 WHEN 'High' THEN 2 WHEN 'Medium' THEN 3 ELSE 4
END;
