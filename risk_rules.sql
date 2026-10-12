-- Transaction Monitoring & Financial Risk Indicator Analysis
-- SQLite pipeline for SAML-D.
-- Input requirement: import the source transaction file as saml_d_raw.
-- This script does not assign laundering typologies or use Is_laundering.
-- It scores sender accounts using transparent heuristic rules only.
--
-- WARNING: DROP statements rebuild derived outputs. Run against a working
-- copy of your database if you need to preserve prior derived tables.

PRAGMA foreign_keys = OFF;
BEGIN TRANSACTION;

DROP VIEW IF EXISTS investigation_queue;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dashboard_cases;
DROP TABLE IF EXISTS dashboard_transactions;
DROP TABLE IF EXISTS investigation_summary;
DROP TABLE IF EXISTS customer_risk_categorized;
DROP TABLE IF EXISTS customer_risk;
DROP TABLE IF EXISTS high_activity_alerts;
DROP TABLE IF EXISTS high_activity_accounts;
DROP TABLE IF EXISTS high_value_alerts;

-- Exploratory high-value transaction extract.
CREATE TABLE high_value_alerts AS
SELECT
    Date,
    Time,
    Sender_account,
    Receiver_account,
    Amount,
    Payment_type,
    Sender_bank_location,
    Receiver_bank_location
FROM saml_d_raw
WHERE Amount > 100000;

-- Sender accounts with more than 300 transactions.
CREATE TABLE high_activity_accounts AS
SELECT
    Sender_account AS account_id,
    COUNT(*) AS transaction_count
FROM saml_d_raw
GROUP BY Sender_account
HAVING COUNT(*) > 300;

-- All transactions belonging to high-activity sender accounts.
CREATE TABLE high_activity_alerts AS
SELECT t.*
FROM saml_d_raw AS t
JOIN high_activity_accounts AS h
  ON t.Sender_account = h.account_id;

-- Start one row per distinct sender account at score zero.
CREATE TABLE customer_risk AS
SELECT
    Sender_account AS account_id,
    0 AS risk_score
FROM saml_d_raw
GROUP BY Sender_account;

-- Rule 1: any transaction over $100,000 adds 50 points.
UPDATE customer_risk
SET risk_score = risk_score + 50
WHERE account_id IN (
    SELECT DISTINCT Sender_account
    FROM saml_d_raw
    WHERE Amount > 100000
);

-- Rule 2: any transaction over $250,000 adds another 30 points.
-- This is additive with Rule 1 by design.
UPDATE customer_risk
SET risk_score = risk_score + 30
WHERE account_id IN (
    SELECT DISTINCT Sender_account
    FROM saml_d_raw
    WHERE Amount > 250000
);

-- Rule 3: more than 300 sent transactions adds 40 points.
UPDATE customer_risk
SET risk_score = risk_score + 40
WHERE account_id IN (
    SELECT account_id
    FROM high_activity_accounts
);

CREATE TABLE customer_risk_categorized AS
SELECT
    account_id,
    risk_score,
    CASE
        WHEN risk_score >= 120 THEN 'Severe'
        WHEN risk_score >= 80 THEN 'High'
        WHEN risk_score >= 40 THEN 'Medium'
        ELSE 'Low'
    END AS risk_level
FROM customer_risk;

-- Transaction-level view for manual review of High/Severe sender accounts.
CREATE VIEW investigation_queue AS
SELECT
    t.Date,
    t.Time,
    t.Sender_account,
    t.Receiver_account,
    t.Amount,
    t.Payment_type,
    t.Sender_bank_location,
    t.Receiver_bank_location,
    r.risk_score,
    r.risk_level
FROM saml_d_raw AS t
JOIN customer_risk_categorized AS r
  ON t.Sender_account = r.account_id
WHERE r.risk_level IN ('High', 'Severe');

-- One row per High/Severe sender account.
CREATE TABLE investigation_summary AS
SELECT
    r.account_id,
    r.risk_level,
    r.risk_score,
    COUNT(*) AS total_transactions,
    SUM(t.Amount) AS total_amount,
    MAX(t.Amount) AS max_transaction_amount,
    COUNT(DISTINCT t.Receiver_account) AS unique_receivers
FROM customer_risk_categorized AS r
JOIN saml_d_raw AS t
  ON r.account_id = t.Sender_account
WHERE r.risk_level IN ('High', 'Severe')
GROUP BY r.account_id, r.risk_level, r.risk_score;

-- Transaction-level data for the Power BI model.
CREATE TABLE dashboard_transactions AS
SELECT
    t.Date,
    t.Time,
    t.Sender_account,
    t.Receiver_account,
    t.Amount,
    t.Payment_type,
    t.Sender_bank_location,
    t.Receiver_bank_location,
    r.risk_level,
    r.risk_score
FROM saml_d_raw AS t
JOIN customer_risk_categorized AS r
  ON t.Sender_account = r.account_id
WHERE r.risk_level IN ('High', 'Severe');

-- Account-level dashboard table. max_transaction_amount is an amount,
-- not a transaction count.
CREATE TABLE dashboard_cases AS
SELECT
    account_id,
    risk_level,
    risk_score,
    total_transactions,
    total_amount,
    max_transaction_amount,
    unique_receivers
FROM investigation_summary;

CREATE TABLE dim_date AS
SELECT DISTINCT Date
FROM dashboard_transactions;

COMMIT;

-- Sanity checks to run after the pipeline:
-- SELECT COUNT(*) FROM saml_d_raw;
-- SELECT risk_level, COUNT(*) FROM customer_risk_categorized GROUP BY risk_level;
-- SELECT COUNT(*) FROM dashboard_cases;
-- SELECT COUNT(*) FROM dashboard_transactions;
