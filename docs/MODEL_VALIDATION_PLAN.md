# Model Validation Plan

This document defines the next validation steps for the rule-based risk scoring workflow.

## 1. Ground-truth validation

Compare the account-level risk flags produced by `risk_rules.sql` with the SAML-D `Is_laundering` ground-truth label.

Measure:

- True positives
- False positives
- True negatives
- False negatives
- Precision
- Recall
- F1 score

The purpose is to quantify how the current transparent rules behave against the available benchmark label rather than treating the rule thresholds as validated by default.

## 2. Threshold sensitivity

Evaluate how the flagged population changes when the current thresholds are varied.

Candidate parameters:

- High-value transaction threshold
- Very-high-value transaction threshold
- High-activity transaction-count threshold
- Overall account risk-score threshold

Record the number of flagged accounts and classification metrics for each configuration.

## 3. Pattern coverage

Measure whether the current rules capture:

- High-value transactions
- High-frequency activity
- Potential structuring patterns
- Repeated transfers involving the same receiver
- Cross-border activity

Patterns that are not represented by the current rules should be documented as model limitations rather than inferred as suspicious by default.

## 4. Reproducibility checks

Before publishing validation results:

1. Start from the documented raw-table schema.
2. Run `risk_rules.sql`.
3. Recreate the dashboard output tables.
4. Compare row counts and key aggregates with the published project results.
5. Record any differences caused by data-version or preprocessing changes.

## 5. Future extensions

After baseline validation, candidate extensions include:

- Explicit structuring rules
- Transaction velocity features
- Network/graph analysis
- Anomaly detection
- Incremental scoring
- Near-real-time monitoring

These extensions should be evaluated against the same validation framework so that additional complexity is supported by measurable evidence.
