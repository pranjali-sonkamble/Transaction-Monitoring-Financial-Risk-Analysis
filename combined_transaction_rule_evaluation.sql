-- Experimental transaction-level AML rule comparison (SQLite).
-- READ-ONLY: no tables are created, dropped, or modified.
-- Run:
-- sqlite3 -header -column database\aml_monitoring.db < sql\combined_transaction_rule_evaluation.sql
--
-- Each transaction is evaluated independently against Is_laundering.
-- Labels are used ONLY for evaluation, never to generate alerts.
--
-- Behavioral window: one calendar day, grouped by the exact source Date value.
-- Rule B: flag transactions from a sender with >10 transactions on that date.
-- Rule C: flag transactions where the same sender sent to the same receiver
--         >=3 times on that date.
-- Rule D: combined OR rule: Amount > 100000 OR Rule B OR Rule C.
--
-- These are exploratory thresholds, not production recommendations.
-- Check date formatting and business meaning before interpreting results.

WITH
normalized AS (
    SELECT
        rowid AS source_row_id,
        Date AS source_date,
        Sender_account AS sender_account,
        Receiver_account AS receiver_account,
        CAST(Amount AS REAL) AS amount_value,
        CASE
            WHEN LOWER(TRIM(CAST(Is_laundering AS TEXT))) IN ('1', 'true', 'yes') THEN 1
            WHEN LOWER(TRIM(CAST(Is_laundering AS TEXT))) IN ('0', 'false', 'no') THEN 0
            ELSE NULL
        END AS actual_label
    FROM saml_d_raw
),
sender_day AS (
    SELECT source_date, sender_account, COUNT(*) AS sender_transactions_that_day
    FROM normalized
    GROUP BY source_date, sender_account
),
sender_receiver_day AS (
    SELECT source_date, sender_account, receiver_account,
           COUNT(*) AS pair_transactions_that_day
    FROM normalized
    GROUP BY source_date, sender_account, receiver_account
),
features AS (
    SELECT
        n.source_row_id,
        n.amount_value,
        n.actual_label,
        CASE WHEN n.amount_value > 100000 THEN 1 ELSE 0 END AS amount_rule,
        CASE WHEN sd.sender_transactions_that_day > 10 THEN 1 ELSE 0 END AS velocity_rule,
        CASE WHEN pd.pair_transactions_that_day >= 3 THEN 1 ELSE 0 END AS repeated_receiver_rule,
        CASE
            WHEN n.amount_value > 100000
              OR sd.sender_transactions_that_day > 10
              OR pd.pair_transactions_that_day >= 3
            THEN 1 ELSE 0
        END AS combined_rule
    FROM normalized AS n
    JOIN sender_day AS sd
      ON sd.source_date IS n.source_date
     AND sd.sender_account IS n.sender_account
    JOIN sender_receiver_day AS pd
      ON pd.source_date IS n.source_date
     AND pd.sender_account IS n.sender_account
     AND pd.receiver_account IS n.receiver_account
),
metrics AS (
    SELECT
        'A: Amount > 100K' AS rule_name,
        COUNT(*) AS total_rows,
        SUM(CASE WHEN actual_label IS NOT NULL THEN 1 ELSE 0 END) AS labeled_rows,
        SUM(CASE WHEN amount_rule = 1 THEN 1 ELSE 0 END) AS alerted_rows,
        SUM(CASE WHEN amount_rule = 1 AND actual_label = 1 THEN 1 ELSE 0 END) AS true_positive_rows,
        SUM(CASE WHEN amount_rule = 1 AND actual_label = 0 THEN 1 ELSE 0 END) AS false_positive_rows,
        SUM(CASE WHEN amount_rule = 0 AND actual_label = 1 THEN 1 ELSE 0 END) AS false_negative_rows,
        SUM(CASE WHEN amount_rule = 0 AND actual_label = 0 THEN 1 ELSE 0 END) AS true_negative_rows,
        SUM(CASE WHEN amount_rule = 1 AND actual_label IS NULL THEN 1 ELSE 0 END) AS alerts_with_unrecognized_label
    FROM features
    UNION ALL
    SELECT
        'B: Sender >10 tx/day',
        COUNT(*),
        SUM(CASE WHEN actual_label IS NOT NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN velocity_rule = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN velocity_rule = 1 AND actual_label = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN velocity_rule = 1 AND actual_label = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN velocity_rule = 0 AND actual_label = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN velocity_rule = 0 AND actual_label = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN velocity_rule = 1 AND actual_label IS NULL THEN 1 ELSE 0 END)
    FROM features
    UNION ALL
    SELECT
        'C: Same pair >=3/day',
        COUNT(*),
        SUM(CASE WHEN actual_label IS NOT NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN repeated_receiver_rule = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN repeated_receiver_rule = 1 AND actual_label = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN repeated_receiver_rule = 1 AND actual_label = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN repeated_receiver_rule = 0 AND actual_label = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN repeated_receiver_rule = 0 AND actual_label = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN repeated_receiver_rule = 1 AND actual_label IS NULL THEN 1 ELSE 0 END)
    FROM features
    UNION ALL
    SELECT
        'D: Combined OR rule',
        COUNT(*),
        SUM(CASE WHEN actual_label IS NOT NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN combined_rule = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN combined_rule = 1 AND actual_label = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN combined_rule = 1 AND actual_label = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN combined_rule = 0 AND actual_label = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN combined_rule = 0 AND actual_label = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN combined_rule = 1 AND actual_label IS NULL THEN 1 ELSE 0 END)
    FROM features
)
SELECT
    rule_name,
    total_rows,
    labeled_rows,
    alerted_rows,
    true_positive_rows,
    false_positive_rows,
    false_negative_rows,
    true_negative_rows,
    ROUND(100.0 * true_positive_rows / NULLIF(true_positive_rows + false_positive_rows, 0), 4) AS precision_pct,
    ROUND(100.0 * true_positive_rows / NULLIF(true_positive_rows + false_negative_rows, 0), 4) AS recall_pct,
    ROUND(100.0 * true_negative_rows / NULLIF(true_negative_rows + false_positive_rows, 0), 4) AS specificity_pct,
    alerts_with_unrecognized_label
FROM metrics
ORDER BY rule_name;
