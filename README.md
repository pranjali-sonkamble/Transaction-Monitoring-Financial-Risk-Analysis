# Transaction Monitoring & Financial Risk Indicator Analysis

## Project Overview
The objective of this project is to simulate an **AML-style transaction monitoring system** that identifies suspicious financial behavior, prioritizes high-risk accounts, and supports investigator decision-making using rule-based risk indicators and interactive dashboards.

The project replicates how financial crime teams analyze large-scale transaction data to detect potential money laundering patterns, generate alerts, and conduct account-level investigations.

---

## Key Risk Indicators Implemented
The transaction monitoring framework incorporates the following AML risk indicators:

- Detection of **high-value transactions** based on abnormal transaction amounts  
- Identification of **excessive transaction frequency**, indicating potential mule or laundering hub behavior  
- **Risk scoring model** combining transaction value and activity volume  
- Classification of accounts into **High** and **Severe** risk levels for investigation prioritization  
- **Geographic analysis** of receiver bank locations to highlight cross-border and high-risk transaction flows  

---

## Investigation Findings
Analysis of over **9.5 million transactions** revealed a small but significant subset of accounts exhibiting high-risk financial behavior. Approximately **13,000 accounts** were classified as **High** or **Severe** risk based on transaction value and activity indicators.

Severe-risk accounts demonstrated patterns consistent with common money laundering typologies, including unusually high transaction volumes, large cumulative transaction values, and dispersion of funds across a high number of unique receiver accounts.

Geographic analysis showed that suspicious transaction volumes were concentrated in a limited number of regions, indicating the presence of potential laundering hubs rather than evenly distributed activity. Time-series analysis further revealed periodic spikes in suspicious transaction value, suggesting bursts of coordinated financial activity rather than random behavior.

---

## Investigation Workflow Enabled
The dashboard supports a realistic AML investigation workflow by enabling analysts to:

- Identify and prioritize high-risk accounts through a ranked case queue  
- Analyze suspicious transaction behavior over time  
- Examine fund flow destinations through geographic visualizations  
- Drill down into individual account activity for detailed investigation  

Interactive slicers allow investigators to dynamically focus on **Severe** cases while retaining visibility into **High-risk** activity.

---

## Tools & Technologies
- **SQL (SQLite)** – Data ingestion, alert rules, and risk scoring logic  
- **Power BI** – AML dashboards, investigation views, and drill-through analysis  
- **CSV-based reporting layer** – Curated datasets for BI consumption  

---

## Data Availability Note
Due to dataset size and confidentiality considerations, raw transaction-level data and full Power BI files are not included in this repository.  
Dashboard screenshots and aggregated investigation outputs are provided to demonstrate analytical results and investigation logic.

---

## Conclusion
This project demonstrates how transaction monitoring systems can be designed using rule-based risk indicators to surface suspicious financial behavior at scale. By combining SQL-based alert logic with interactive Power BI dashboards, the system supports realistic AML investigation workflows, risk prioritization, and data-driven decision-making.

---

## Author
Pranjali
