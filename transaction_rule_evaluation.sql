-- Transaction-level amount-threshold evaluation against the source label.
-- READ-ONLY: this script does not create, drop, or modify tables.
-- Run from the directory containing your SQLite database:
-- sqlite3 -header -column saml_d.db < transaction_rule_evaluation.sql
--
-- Important:
-- * This is a deliberately simple baseline, not a laundering classifier.
-- * Each row is evaluated independently; account-level risk tiers are not used.
-- * Labels are used only for evaluation, never to generate alerts.
-- * Adjust the label mapping if the source uses a different encoding.
-- * Amount thresholds are strict: Amount > threshold.

WITH
thresholds(threshold_amount) AS (
    VALUES (50000.0), (100000.0), (250000.0), (500000.0)
),
normalized AS (
    SELECT
        CAST(Amount AS REAL) AS amount_value,
        CASE
            WHEN LOWER(TRIM(CAST(Is_laundering AS TEXT))) IN ('1', 'true', 'yes') THEN 1
            WHEN LOWER(TRIM(CAST(Is_laundering AS TEXT))) IN ('0', 'false', 'no') THEN 0
            ELSE NULL
        END AS actual_positive
    FROM saml_d_raw
),
counts AS (
    SELECT
        t.threshold_amount,
        COUNT(*) AS total_rows,
        SUM(CASE WHEN n.actual_positive IS NOT NULL THEN 1 ELSE 0 END) AS labeled_rows,
        SUM(CASE WHEN n.actual_positive = 1 THEN 1 ELSE 0 END) AS actual_positive_rows,
        SUM(CASE WHEN n.actual_positive = 0 THEN 1 ELSE 0 END) AS actual_negative_rows,
        SUM(CASE WHEN n.actual_positive = 1 AND n.amount_value > t.threshold_amount THEN 1 ELSE 0 END) AS true_positive_rows,
        SUM(CASE WHEN n.actual_positive = 0 AND n.amount_value > t.threshold_amount THEN 1 ELSE 0 END) AS false_positive_rows,
        SUM(CASE WHEN n.actual_positive = 1 AND COALESCE(n.amount_value > t.threshold_amount, 0) = 0 THEN 1 ELSE 0 END) AS false_negative_rows,
        SUM(CASE WHEN n.actual_positive = 0 AND NOT (n.amount_value > t.threshold_amount) THEN 1 ELSE 0 END) AS true_negative_rows,
        SUM(CASE WHEN n.actual_positive IS NULL AND n.amount_value > t.threshold_amount THEN 1 ELSE 0 END) AS alerts_with_unrecognized_label
    FROM thresholds AS t
    CROSS JOIN normalized AS n
    GROUP BY t.threshold_amount
)
SELECT
    threshold_amount,
    total_rows,
    labeled_rows,
    actual_positive_rows,
    actual_negative_rows,
    true_positive_rows,
    false_positive_rows,
    false_negative_rows,
    true_negative_rows,
    ROUND(100.0 * true_positive_rows / NULLIF(true_positive_rows + false_positive_rows, 0), 4) AS precision_pct,
    ROUND(100.0 * true_positive_rows / NULLIF(true_positive_rows + false_negative_rows, 0), 4) AS recall_pct,
    ROUND(100.0 * true_negative_rows / NULLIF(true_negative_rows + false_positive_rows, 0), 4) AS specificity_pct,
    alerts_with_unrecognized_label
FROM counts
ORDER BY threshold_amount;
