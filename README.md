# Transaction Monitoring & Financial Risk Indicator Analysis

An AML-style (Anti-Money Laundering) transaction monitoring system that identifies suspicious financial behavior, prioritizes high-risk accounts, and supports investigator decision-making using rule-based risk scoring and interactive Power BI dashboards.

---

## Table of Contents
- [Problem Statement](#problem-statement)
- [Dataset](#dataset)
- [Architecture / Data Flow](#architecture--data-flow)
- [Methodology](#methodology)
- [Dashboard Preview](#dashboard-preview)
- [Key Findings](#key-findings)
- [Business Recommendations](#business-recommendations)
- [How to Reproduce](#how-to-reproduce)
- [Limitations & Future Work](#limitations--future-work)
- [Tools & Technologies](#tools--technologies)

---

## Problem Statement

Financial institutions must flag suspicious transaction patterns for regulatory compliance (AML/KYC). Manually reviewing millions of transactions is infeasible — this project simulates how a financial crime/compliance team would build a **rule-based monitoring system** to surface the highest-risk accounts from a large transaction dataset, replacing "review everything" with "review what matters first."

---

## Dataset

This project uses **SAML-D**, a published synthetic anti-money laundering benchmark dataset (Oztas et al.), containing **9,504,852 transactions** across 12 features, including sender/receiver account IDs, amount, payment type, and sender/receiver bank locations. The dataset spans transactions from **November 2022 to July 2023** in this analysis. It was chosen because it's purpose-built for AML research — it models realistic laundering typologies (structuring, fan-out, cross-border layering) rather than generic transaction noise, and unlike real bank data, it can be shared and analyzed without privacy/regulatory restrictions.

> Note: SAML-D also ships with a ground-truth `Is_laundering` label. This project's rule-based scores were **not** validated against that label — see [Limitations](#limitations--future-work).

---

## Architecture / Data Flow

```
SAML-D Transaction Data (saml_d_raw)
        │
        ▼
SQL (SQLite) — Rule-based Risk Scoring (risk_rules.sql)
        │
        ▼
customer_risk_categorized — Account-level Risk Tiers
        │
        ▼
investigation_summary / dashboard_cases.csv — Curated Case Output
        │
        ▼
Power BI — Risk Overview + Case Investigation Dashboards
```

---

## Methodology

### Risk Scoring Logic

Each account starts at a risk score of 0. Points are added based on three independent rule checks against that account's transaction history:

| Rule | Condition | Points |
|------|-----------|--------|
| High-value transaction | Any transaction > $100,000 | +50 |
| Very high-value transaction | Any transaction > $250,000 | +30 |
| High activity | More than 300 total transactions sent | +40 |

### Risk Tiers

| Tier | Score | How it's triggered | Accounts | % |
|------|-------|--------------------|----------|---|
| **Severe** | 120 | All three rules triggered (>$100K **and** >$250K **and** >300 txns) | 6,433 | 47.9% |
| **High** | 90 | >$100K and >300 txns, but no transaction over $250K | 2,909 | — |
| **High** | 80 | >$100K and >$250K, but ≤300 txns | 4,082 | — |
| High (combined) | 80–90 | — | 6,991 | 52.1% |
| Medium / Low | <80 | One or zero rules triggered | *(excluded from dashboard — see note below)* | — |

> Only accounts scoring 80+ (High/Severe) were carried into the investigation dashboards; Medium/Low-risk accounts were scored but not surfaced for manual review, keeping the investigation queue focused.

This is a deliberately simple, additive rule model rather than a weighted/ML-based one — the tradeoff is interpretability and regulatory explainability (a compliance officer can see exactly *why* an account was flagged) at the cost of missing more subtle multi-factor patterns an anomaly-detection model might catch.

---

## Dashboard Preview

### Risk Overview – Suspicious Activity Monitoring
![Risk Overview Dashboard](Risk_Overview_Dashboard.png)

Gives a portfolio-level view: **13,424 accounts** flagged out of the monitored transaction pool, with **$41.17B** in total flagged transaction value and an average monitored transaction of **$8.66K**. The severity donut, geographic map, and daily value trend let an investigator triage where to look first before drilling into individual cases.

### Case Investigation – Account-Level Deep Dive
![Case Investigation Dashboard](Case_Investigation_View.png)

Drill-through view for a single flagged account: full transaction history, receiver accounts, payment type, and a daily transaction-count chart to spot bursts of activity.

---

## Key Findings

- Out of the monitored pool, **13,424 accounts (13K)** were classified as High or Severe risk, representing **$41.17B** in flagged transaction value — split almost evenly between **Severe (47.9%)** and **High (52.1%)**.
- The most severe accounts show a consistent fingerprint: **700+ transactions**, **50+ unique receiver accounts**, and several million dollars in cumulative value each — e.g. one account sent 743 transactions to 58 distinct receivers totaling $5.05M. This fan-out pattern (many receivers, high frequency) is a classic laundering/"smurfing" signature, distinct from a single large one-off transfer.
- The case-level drill-through surfaced a concrete structuring pattern: one account made **11 cross-border transfers to the same receiver within a single day**, each individually in the $20K–21K range — well under any single-transaction alert threshold, but cumulatively over $230K in a day. This is exactly the kind of activity a pure "amount > $100K" rule would miss, which is why the frequency-based rule (+40 for >300 transactions) matters as a complementary signal.
- The geographic map shows flagged activity concentrated across Europe, though a full country-by-country ranking wasn't computed in this iteration (see Limitations).
- The daily transaction-value trend (Nov 2022–Jul 2023) is fairly consistent in the $100M–150M/day range rather than showing isolated spikes — suspicious activity here looks more like a steady baseline behavior than rare bursts, which is itself a useful finding: it suggests the flagged accounts behave this way *routinely*, not just during isolated incidents.

## Business Recommendations

- Prioritize the ~700 accounts scoring **120 (Severe)** for manual investigation first — they account for the majority of flagged value and show the clearest multi-signal fingerprint (high value + high frequency + wide fan-out).
- Cross-reference top-flagged accounts' cross-border transfers with receiver-country risk ratings, since geographic concentration was visible but not yet formally ranked.
- Treat the structuring pattern (many similar-sized transactions to one receiver in a short window) as its own explicit rule going forward, rather than relying on the frequency rule to catch it indirectly.

---

## How to Reproduce

1. Download the SAML-D dataset (published by Oztas et al., available via Kaggle) and load it into SQLite as `saml_d_raw`.
2. Run `risk_rules.sql` end-to-end — it builds the risk scoring tables, categorizes accounts into tiers, and produces `dashboard_cases.csv`.
3. Open the Power BI file and point it at `dashboard_cases.csv` / the underlying transaction tables to regenerate the dashboards.

*(Raw data and the full `.pbix` file aren't included in this repo due to size — `dashboard_cases.csv` and the dashboard screenshots are provided so the output is reproducible from `risk_rules.sql` alone.)*

---

## Limitations & Future Work

- **No validation against ground truth.** SAML-D includes an `Is_laundering` label, but this project's rule thresholds ($100K / $250K / 300 transactions) were chosen heuristically and not checked against it. A natural next step: compute precision/recall of the current rules against the true label, and use that to justify or retune the thresholds.
- **No entity-resolution or network view.** Accounts are scored independently; a graph-based approach (shared receivers, device/IP overlap where available) would catch coordinated multi-account laundering rings that this account-by-account scoring misses.
- **Geographic analysis is visual, not quantified.** The map shows concentration in Europe, but a ranked table of top sender/receiver-location pairs by flagged value wasn't built into the final dashboard — worth adding.
- **Static, batch-scored.** Everything here is computed once over the full dataset; a production system would need incremental/near-real-time scoring as new transactions arrive.
- **Full raw data and `.pbix` withheld** for repo size — reproducibility is via the SQL script and dataset source instead.

---

## Tools & Technologies

- **SQL (SQLite)** — data ingestion, rule-based risk scoring, tiering logic
- **Power BI** — Risk Overview and Case Investigation dashboards, drill-through analysis
- **Dataset:** SAML-D synthetic AML benchmark (Oztas et al.)

---

## Author

Pranjali Sonkamble
