-- Faster experimental transaction-level AML rule comparison (SQLite).
-- Creates TEMP tables only; these disappear when the SQLite session closes.
-- Does NOT modify persistent tables, risk_rules.sql outputs, or the Power BI model.
-- Run:
-- sqlite3 -header -column database\aml_monitoring.db < sql\combined_transaction_rule_evaluation_fast.sql
--
-- Rule A: Amount > 100000
-- Rule B: sender has >10 transactions on the same source Date
-- Rule C: same sender->receiver pair occurs >=3 times on the same source Date
-- Rule D: A OR B OR C
-- Date is grouped exactly as stored (calendar-day key), not a rolling 24-hour window.
-- Labels are used only for evaluation, never to generate alerts.

.headers on
.mode column
PRAGMA temp_store = FILE;

DROP TABLE IF EXISTS temp.sender_day_counts;
DROP TABLE IF EXISTS temp.sender_receiver_day_counts;

CREATE TEMP TABLE sender_day_counts AS
SELECT Date AS source_date, Sender_account AS sender_account, COUNT(*) AS tx_count
FROM saml_d_raw
GROUP BY Date, Sender_account;

CREATE INDEX temp.idx_sender_day_counts
ON sender_day_counts(source_date, sender_account);

CREATE TEMP TABLE sender_receiver_day_counts AS
SELECT Date AS source_date, Sender_account AS sender_account,
       Receiver_account AS receiver_account, COUNT(*) AS pair_tx_count
FROM saml_d_raw
GROUP BY Date, Sender_account, Receiver_account;

CREATE INDEX temp.idx_sender_receiver_day_counts
ON sender_receiver_day_counts(source_date, sender_account, receiver_account);

WITH features AS (
    SELECT
        CAST(t.Amount AS REAL) AS amount_value,
        CASE
            WHEN LOWER(TRIM(CAST(t.Is_laundering AS TEXT))) IN ('1', 'true', 'yes') THEN 1
            WHEN LOWER(TRIM(CAST(t.Is_laundering AS TEXT))) IN ('0', 'false', 'no') THEN 0
            ELSE NULL
        END AS actual_label,
        CASE WHEN CAST(t.Amount AS REAL) > 100000 THEN 1 ELSE 0 END AS amount_rule,
        CASE WHEN COALESCE(sd.tx_count, 0) > 10 THEN 1 ELSE 0 END AS velocity_rule,
        CASE WHEN COALESCE(pd.pair_tx_count, 0) >= 3 THEN 1 ELSE 0 END AS repeated_receiver_rule
    FROM saml_d_raw AS t
    LEFT JOIN sender_day_counts AS sd
      ON sd.source_date IS t.Date
     AND sd.sender_account IS t.Sender_account
    LEFT JOIN sender_receiver_day_counts AS pd
      ON pd.source_date IS t.Date
     AND pd.sender_account IS t.Sender_account
     AND pd.receiver_account IS t.Receiver_account
),
predictions AS MATERIALIZED (
    SELECT *,
        CASE WHEN amount_rule = 1 OR velocity_rule = 1 OR repeated_receiver_rule = 1
             THEN 1 ELSE 0 END AS combined_rule
    FROM features
),
metrics AS (
    SELECT
        'A: Amount > 100K' AS rule_name,
        COUNT(*) AS total_rows,
        SUM(CASE WHEN actual_label IS NOT NULL THEN 1 ELSE 0 END) AS labeled_rows,
        SUM(amount_rule) AS alerted_rows,
        SUM(CASE WHEN amount_rule = 1 AND actual_label = 1 THEN 1 ELSE 0 END) AS true_positive_rows,
        SUM(CASE WHEN amount_rule = 1 AND actual_label = 0 THEN 1 ELSE 0 END) AS false_positive_rows,
        SUM(CASE WHEN amount_rule = 0 AND actual_label = 1 THEN 1 ELSE 0 END) AS false_negative_rows,
        SUM(CASE WHEN amount_rule = 0 AND actual_label = 0 THEN 1 ELSE 0 END) AS true_negative_rows,
        SUM(CASE WHEN amount_rule = 1 AND actual_label IS NULL THEN 1 ELSE 0 END) AS alerts_with_unrecognized_label
    FROM predictions
    UNION ALL
    SELECT
        'B: Sender >10 tx/day', COUNT(*),
        SUM(CASE WHEN actual_label IS NOT NULL THEN 1 ELSE 0 END),
        SUM(velocity_rule),
        SUM(CASE WHEN velocity_rule = 1 AND actual_label = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN velocity_rule = 1 AND actual_label = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN velocity_rule = 0 AND actual_label = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN velocity_rule = 0 AND actual_label = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN velocity_rule = 1 AND actual_label IS NULL THEN 1 ELSE 0 END)
    FROM predictions
    UNION ALL
    SELECT
        'C: Same pair >=3/day', COUNT(*),
        SUM(CASE WHEN actual_label IS NOT NULL THEN 1 ELSE 0 END),
        SUM(repeated_receiver_rule),
        SUM(CASE WHEN repeated_receiver_rule = 1 AND actual_label = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN repeated_receiver_rule = 1 AND actual_label = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN repeated_receiver_rule = 0 AND actual_label = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN repeated_receiver_rule = 0 AND actual_label = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN repeated_receiver_rule = 1 AND actual_label IS NULL THEN 1 ELSE 0 END)
    FROM predictions
    UNION ALL
    SELECT
        'D: Combined OR rule', COUNT(*),
        SUM(CASE WHEN actual_label IS NOT NULL THEN 1 ELSE 0 END),
        SUM(combined_rule),
        SUM(CASE WHEN combined_rule = 1 AND actual_label = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN combined_rule = 1 AND actual_label = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN combined_rule = 0 AND actual_label = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN combined_rule = 0 AND actual_label = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN combined_rule = 1 AND actual_label IS NULL THEN 1 ELSE 0 END)
    FROM predictions
)
SELECT
    rule_name, total_rows, labeled_rows, alerted_rows,
    true_positive_rows, false_positive_rows, false_negative_rows, true_negative_rows,
    ROUND(100.0 * true_positive_rows / NULLIF(true_positive_rows + false_positive_rows, 0), 4) AS precision_pct,
    ROUND(100.0 * true_positive_rows / NULLIF(true_positive_rows + false_negative_rows, 0), 4) AS recall_pct,
    ROUND(100.0 * true_negative_rows / NULLIF(true_negative_rows + false_positive_rows, 0), 4) AS specificity_pct,
    alerts_with_unrecognized_label
FROM metrics
ORDER BY rule_name;
