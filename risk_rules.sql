SELECT COUNT(*) FROM saml_d_raw;

select 
min(Amount) as min_amt,
max(Amount) as max_amt,
avg(Amount) as avg_amt
from saml_d_raw;

select Amount, Sender_account, Receiver_account, Payment_type
from saml_d_raw
order by Amount DESC
limit 10;

SELECT
Sender_bank_location,
Receiver_bank_location,
count(*) as txn_count
from saml_d_raw
group by Sender_bank_location, Receiver_bank_location
order by txn_count DESC
limit 10;

select Sender_account,
count(*) as txn_volume
from saml_d_raw
group by Sender_account
order by txn_volume DESC
limit 10;

CREATE TABLE high_value_alerts AS
SELECT 
    Time,
    Date,
    Sender_account,
    Receiver_account,
    Amount,
    Payment_type,
    Sender_bank_location,
    Receiver_bank_location
FROM saml_d_raw
WHERE Amount > 100000;

select count(*) from high_value_alerts;

create table high_value_accounts as
SELECT
Sender_account,
count(*) as txn_volume
from saml_d_raw
group by Sender_account
having txn_volume > 300;

alter table high_value_accounts
rename to high_activit_accounts;

select count(*) from high_activit_accounts;

create table high_activit_alerts as
select t.*
from saml_d_raw t
join high_activit_accounts h
on t.Sender_account = h.Sender_account;

select count(*) from high_activit_alerts;

create table customer_risk as
SELECT
Sender_account as account_id,
0 as risk_score
from saml_d_raw
group by Sender_account;

update customer_risk set risk_score = risk_score + 50
where account_id in (select distinct Sender_account
from saml_d_raw
where Amount > 100000);

update customer_risk set risk_score = risk_score + 30
where account_id in (
select distinct Sender_account
from saml_d_raw
where Amount > 250000
);

update customer_risk set risk_score = risk_score + 40
where account_id in(
select Sender_account
from high_activit_accounts
);

select * from customer_risk
order by risk_score DESC limit 20;

select risk_score, count(*) as accounts
from customer_risk 
group by risk_score
order by risk_score DESC;

create table customer_risk_categorized as select
account_id,risk_score,
CASE
when risk_score >= 120 then 'Severe'
when risk_score >= 80 then 'High'
when risk_score >= 40 then 'Medium'
else 'low'
end as risk_level
from customer_risk;

select risk_level, count(*)
from customer_risk_categorized
group by risk_level
order by count(*) desc;

create view investigation_queue as
SELECT
t.date,
t.time,
t.Sender_account,
t.Receiver_account,
t.Amount,
t.Payment_type,
t.Sender_bank_location,
t.Receiver_bank_location,
r.risk_score,
r.risk_level
from saml_d_raw t
join customer_risk_categorized r
on t.Sender_account = r.account_id
where r.risk_level in ('High','Severe');

select count(*) from investigation_queue;

create table investigation_summary as
select 
r.account_id,
r.risk_level,
r.risk_score,
count(*) as total_transactions,
sum(t.Amount) as total_amount,
max(t.Amount) as max_transactions,
count(distinct t.Receiver_account) as unique_receivers
from customer_risk_categorized r
join saml_d_raw t
on r.account_id = t.Sender_account
where r.risk_level in ('High','Severe')
group by r.account_id, r.risk_level, r.risk_score;

select * from investigation_summary
order by risk_score desc, total_amount DESC limit 10;

create table dashboard_transactions as
select * 
from saml_d_raw
where Sender_account in (
select account_id
from customer_risk_categorized
where risk_level in('High','Severe')
);

create table dashboard_transactions as select
t.date,
t.time,
t.Sender_account,
t.Receiver_account,
t.Amount,
t.Payment_type,
t.Sender_bank_location,
t.Receiver_bank_location,
r.risk_level,
r.risk_score
from saml_d_raw t
join customer_risk_categorized r
on t.Sender_account = r.account_id
where r.risk_level in ('High','Severe');

SELECT COUNT(*) FROM dashboard_transactions;

CREATE TABLE dashboard_cases AS
SELECT
    account_id,
    risk_level,
    risk_score,
    total_transactions,
    total_amount,
    max_transactions,
    unique_receivers
FROM investigation_summary;

SELECT COUNT(*) FROM dashboard_cases;

CREATE TABLE dim_date AS
SELECT DISTINCT
    Date
FROM dashboard_transactions;

