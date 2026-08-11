create database msme;
use msme;

-- Table 1: MSME Profiles
CREATE TABLE msme_profiles (
  msme_id        VARCHAR(12) PRIMARY KEY,
  business_name  VARCHAR(100),
  category       VARCHAR(50),   -- Retail, Textile, Pharma, FMCG, IT
  business_age_yrs NUMERIC(4,1),
  state          VARCHAR(30),
  gst_registered BOOLEAN,
  annual_turnover NUMERIC(14,2),
  employee_count INT
);

-- Table 2: Loan Records
CREATE TABLE loan_records (
  loan_id        VARCHAR(15) PRIMARY KEY,
  msme_id        VARCHAR(12) REFERENCES msme_profiles,
  loan_amount    NUMERIC(12,2),
  disbursement_dt DATE,
  tenure_days    INT,
  interest_rate  NUMERIC(5,2),
  loan_status    VARCHAR(20),  -- Active/Closed/NPA
  delinquency_flag BOOLEAN
);

-- Table 3: Transaction Logs
CREATE TABLE txn_logs (
  txn_id         SERIAL PRIMARY KEY,
  msme_id        VARCHAR(12) REFERENCES msme_profiles,
  txn_month      DATE,
  monthly_txn_vol NUMERIC(12,2),
  txn_count      INT,
  avg_txn_value  NUMERIC(10,2)
);

-- Table 4: Repayment History
CREATE TABLE repayment_history (
  repay_id       SERIAL PRIMARY KEY,
  loan_id        VARCHAR(15) REFERENCES loan_records,
  due_date       DATE,
  paid_date      DATE,
  amount_due     NUMERIC(10,2),
  amount_paid    NUMERIC(10,2),
  days_overdue   INT        -- NULL if paid on time
);
select * from repayment_history;
select * from txn_logs;
select * from loan_records;
select * from msme_profiles;

select 'msme_profiles' as tbl, COUNT(*) as row_count from msme_profiles
union all
select 'loan_records', count(*) from loan_records
union all
select 'txn_logs', count(*) from txn_logs
union all
select 'repayment_history', count(*) from repayment_history;

SELECT
    m.msme_id,
    m.business_name,
    m.category,
    m.business_age_yrs,
    l.loan_id,
    l.loan_amount,
    l.loan_status,
    l.delinquency_flag
FROM msme_profiles m
LEFT JOIN loan_records l
    ON m.msme_id = l.msme_id
LIMIT 20;

-- Verify: do the key counts match?
SELECT
    COUNT(DISTINCT m.msme_id)  AS total_msmes,
    COUNT(DISTINCT l.loan_id)   AS total_loans
FROM msme_profiles m
LEFT JOIN loan_records l 
ON m.msme_id = l.msme_id;

SELECT
    m.msme_id,
    m.category,
    m.business_age_yrs,
    l.loan_id,
    l.loan_amount,
    l.delinquency_flag,

-- Aggregate the 12 monthly rows into one signal per MSME
ROUND(AVG(t.monthly_txn_vol), 2) AS avg_monthly_vol,
ROUND(STDDEV(t.monthly_txn_vol), 2) AS txn_volatility,
COUNT(t.txn_month) AS active_months,
SUM(t.txn_count) AS total_txn_count
FROM msme_profiles m
LEFT JOIN loan_records l ON m.msme_id = l.msme_id
LEFT JOIN txn_logs t     ON m.msme_id = t.msme_id

-- Every non-aggregated column MUST appear here in MySQL
GROUP BY
    m.msme_id, m.category, m.business_age_yrs,
    l.loan_id, l.loan_amount, l.delinquency_flag
LIMIT 10;

SELECT
    m.msme_id,
    m.business_name,
    m.category,
    m.state,
    m.business_age_yrs,
    m.annual_turnover,
    m.gst_registered,
    l.loan_id,
    l.loan_amount,
    l.tenure_days,
    l.interest_rate,
    l.loan_status,
    l.delinquency_flag,
    
-- Transaction signals (from txn_logs)
ROUND(AVG(t.monthly_txn_vol), 2) AS avg_monthly_vol,
ROUND(STDDEV(t.monthly_txn_vol), 2) AS txn_volatility,
COUNT(t.txn_month) AS active_months,

-- Repayment signals (from repayment_history)
ROUND(AVG(IFNULL(r.days_overdue, 0)), 2) AS avg_days_overdue,
ROUND(SUM(r.amount_paid) / NULLIF(SUM(r.amount_due), 0), 4) AS repayment_ratio,
COUNT(CASE WHEN r.days_overdue > 30 THEN 1 END) AS late_30d,
COUNT(CASE WHEN r.days_overdue > 90 THEN 1 END) AS late_90d,
COUNT(CASE WHEN r.paid_date IS NULL THEN 1 END) AS unpaid_emis
FROM msme_profiles m
LEFT JOIN loan_records l
	ON m.msme_id = l.msme_id
LEFT JOIN txn_logs t 
	ON m.msme_id = t.msme_id
LEFT JOIN repayment_history r 
	ON l.loan_id  = r.loan_id

GROUP BY
    m.msme_id, m.business_name, m.category, m.state,
    m.business_age_yrs, m.annual_turnover, m.gst_registered,
    l.loan_id, l.loan_amount, l.tenure_days,
    l.interest_rate, l.loan_status, l.delinquency_flag

ORDER BY avg_monthly_vol DESC
LIMIT 20;

CREATE OR REPLACE VIEW v_credit_master AS
SELECT
    m.msme_id,
    m.business_name,
    m.category,
    m.state,
    m.business_age_yrs,
    m.annual_turnover,
    m.gst_registered,
    m.employee_count,
    l.loan_id,
    l.loan_amount,
    l.disbursement_dt,
    l.tenure_days,
    l.interest_rate,
    l.loan_status,
    l.delinquency_flag,
    
ROUND(AVG(t.monthly_txn_vol), 2) AS avg_monthly_vol,
ROUND(STDDEV(t.monthly_txn_vol), 2) AS txn_volatility,
COUNT(t.txn_month) AS active_months,
SUM(t.txn_count) AS total_txns,
ROUND(AVG(IFNULL(r.days_overdue, 0)), 2) AS avg_days_overdue,
ROUND(SUM(r.amount_paid) / NULLIF(SUM(r.amount_due), 0), 4) AS repayment_ratio,
COUNT(CASE WHEN r.days_overdue > 30 THEN 1 END) AS late_30d,
COUNT(CASE WHEN r.days_overdue > 90 THEN 1 END) AS late_90d,
COUNT(CASE WHEN r.paid_date IS NULL THEN 1 END) AS unpaid_emis
FROM msme_profiles m
LEFT JOIN loan_records l ON m.msme_id = l.msme_id
LEFT JOIN txn_logs t ON m.msme_id = t.msme_id
LEFT JOIN repayment_history r ON l.loan_id  = r.loan_id

GROUP BY
    m.msme_id, m.business_name, m.category, m.state,
    m.business_age_yrs, m.annual_turnover,
    m.gst_registered, m.employee_count,
    l.loan_id, l.loan_amount, l.disbursement_dt,
    l.tenure_days, l.interest_rate,
    l.loan_status, l.delinquency_flag;

-- Verify the view works:
SELECT COUNT(*) FROM v_credit_master;

WITH base AS (
    SELECT * FROM v_credit_master
)
SELECT
    *,
    -- Rank by txn volume within each sector (1 = top performer)
    RANK() OVER (
        PARTITION BY category
        ORDER BY avg_monthly_vol DESC
    ) AS txn_rank_in_sector,

    -- Percentile position of loan size within sector
    PERCENT_RANK() OVER (
        PARTITION BY category
        ORDER BY loan_amount
    ) AS loan_size_pctile

FROM base
ORDER BY category, txn_rank_in_sector
LIMIT 50;

-- Default rate by sector
SELECT
    category,
    COUNT(*) AS total_loans,
    SUM(delinquency_flag) AS defaults,
    ROUND(SUM(delinquency_flag)*100.0/COUNT(*), 2) AS default_rate_pct,
    ROUND(AVG(loan_amount), 0) AS avg_loan_amt,
    ROUND(AVG(avg_days_overdue), 1) AS avg_days_late
FROM v_credit_master
GROUP BY category
ORDER BY default_rate_pct DESC;

-- Default rate by business age cohort
SELECT
    CASE
        WHEN business_age_yrs < 1  THEN 'Under 1 yr'
        WHEN business_age_yrs < 3  THEN '1–3 yrs'
        WHEN business_age_yrs < 5  THEN '3–5 yrs'
        WHEN business_age_yrs < 10 THEN '5–10 yrs'
        ELSE '10+ yrs'
    END AS age_bucket,
    COUNT(*) AS total,
    ROUND(AVG(delinquency_flag)*100, 2) AS default_rate_pct,
    ROUND(AVG(repayment_ratio), 3) AS avg_repayment_ratio
FROM v_credit_master
GROUP BY age_bucket
ORDER BY default_rate_pct DESC;

-- Monthly default trend (feeds Power BI line chart)
SELECT
    DATE_FORMAT(disbursement_dt, '%Y-%m') AS month,
    COUNT(*) AS loans_disbursed,
    SUM(delinquency_flag) AS defaults,
    ROUND(AVG(delinquency_flag)*100, 2) AS default_rate_pct,
    ROUND(SUM(loan_amount), 0) AS portfolio_value
FROM v_credit_master
GROUP BY month
ORDER BY month;

-- NPA ratio (total value of NPA loans ÷ total portfolio)
SELECT
    ROUND(SUM(CASE WHEN loan_status = 'NPA'
        THEN loan_amount ELSE 0 END) * 100 /
        SUM(loan_amount), 2) AS npa_ratio_pct,
    ROUND(SUM(loan_amount), 0) AS total_portfolio_value
FROM v_credit_master;

select * from msme_scored;