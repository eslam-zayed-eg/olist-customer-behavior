/* =====================================================================
   FILE      : sql/03_analysis.sql
   PROJECT   : BI-Olist-Analytics
   PURPOSE   : Answers to the 12 questions: G1-G3 (common), the 7 questions
               of the assigned track, and O1-O2.
   RUN ORDER : after 02_validation.sql (needs the views of Part 5-B).
   STATUS    : GENERATED CODE - NOT YET TESTED ON A REAL SQL SERVER.
               Expected values in comments were measured on the original
               CSV files with Python/pandas.

   COMMON RULES (PDF, Section 8)
     * Window            : purchase date 2017-01-01 <= d < 2018-09-01
     * Population        : delivered orders, unless a question says otherwise
     * Merchandise sales : SUM(price) of item rows (no freight), in BRL
     * AOV               : merchandise sales / DISTINCT delivered orders
     * People            : DISTINCT customer_unique_id
     * Rates             : numerator and denominator are always shown
     * Division          : NULL-safe, with NULLIF(denominator, 0)
   ===================================================================== */
USE OlistBI;
GO
SET NOCOUNT ON;
GO

/* =====================================================================
   G1 - How many orders were placed, and what is their status?
   PURPOSE : size of the order book and share of each status; headline
             figures of delivered orders.
   INPUT   : dbo.vw_orders_in_scope (grain: order, ALL statuses)
   OUTPUT  : G1.1 one row per order_status
             G1.2 one summary row for delivered orders
   SQL     : scalar subquery used as the percentage denominator.
   DENOMINATOR (G1.1): ALL orders purchased in the window (99,092).
   DENOMINATOR (G1.2): same 99,092 for the delivered share.
   Expected G1.1: delivered 96,211 (97.09%) | shipped 1,097 | unavailable 602 |
                  canceled 580 | processing 299 | invoiced 296 | created 5 | approved 2
   Expected G1.2: delivered_orders 96,211 | distinct_customers 93,104 |
                  merchandise_sales 13,181,027.13 | avg_order_value 137.00
   ===================================================================== */
-- G1.1 order-status table
SELECT s.order_status,
       COUNT(*) AS orders,
       (SELECT COUNT(*) FROM dbo.vw_orders_in_scope) AS all_orders_in_window,   -- scalar subquery = denominator
       CAST(100.0 * COUNT(*) / (SELECT COUNT(*) FROM dbo.vw_orders_in_scope) AS DECIMAL(6,2)) AS pct_of_all_orders
FROM dbo.vw_orders_in_scope AS s
GROUP BY s.order_status
ORDER BY orders DESC, s.order_status;

-- G1.2 delivered-order summary
SELECT COUNT(*)                                   AS delivered_orders,
       COUNT(DISTINCT d.customer_unique_id)       AS distinct_customers,   -- people, not customer_id
       SUM(v.merchandise_value)                   AS merchandise_sales_brl,
       CAST(SUM(v.merchandise_value) / NULLIF(COUNT(*), 0) AS DECIMAL(18,2)) AS avg_order_value_brl,
       (SELECT COUNT(*) FROM dbo.vw_orders_in_scope) AS all_orders_in_window,  -- scalar subquery
       CAST(100.0 * COUNT(*) / (SELECT COUNT(*) FROM dbo.vw_orders_in_scope) AS DECIMAL(6,2)) AS delivered_pct_of_all_orders
FROM dbo.vw_delivered_orders AS d
JOIN dbo.vw_order_values     AS v ON v.order_id = d.order_id;    -- 1 row per order on both sides
GO

/* =====================================================================
   G2 - How do sales change from month to month?
   PURPOSE : monthly trend of merchandise sales, orders, AOV, growth and
             cumulative sales.
   INPUT   : dbo.vw_delivered_orders JOIN dbo.vw_order_values (grain: order)
   OUTPUT  : one row per purchase month, ALL 20 months Jan-2017 .. Aug-2018
   SQL     : CTEs (months -> monthly -> filled) + window functions:
               LAG(...)  OVER (ORDER BY month_start)            previous month
               SUM(...)  OVER (ORDER BY month_start ROWS UNBOUNDED PRECEDING) running total
   GROWTH  : (current - previous) / previous * 100; NULL if there is no
             previous month or the previous value is 0.
   Expected: 20 rows | SUM(delivered_orders) = 96,211 |
             last running_sales_total = 13,181,027.13 |
             Jan-2017 sales 111,798.36 (750 orders, growth NULL) |
             Feb-2017 growth 109.51 | Nov-2017 sales 987,765.37 (7,289 orders)
   ===================================================================== */
WITH months AS (                                     -- every month of the window
    SELECT CAST('2017-01-01' AS DATE) AS month_start
    UNION ALL
    SELECT DATEADD(MONTH, 1, month_start)
    FROM months
    WHERE month_start < '2018-08-01'
),
monthly AS (                                         -- grain: one row per month that has orders
    SELECT d.purchase_month,
           COUNT(*)                AS delivered_orders,
           SUM(v.merchandise_value) AS merchandise_sales
    FROM dbo.vw_delivered_orders AS d
    JOIN dbo.vw_order_values     AS v ON v.order_id = d.order_id
    GROUP BY d.purchase_month
),
filled AS (                                          -- grain: one row per month (zeros for empty months)
    SELECT m.month_start,
           COALESCE(mo.delivered_orders, 0)   AS delivered_orders,
           COALESCE(mo.merchandise_sales, 0)  AS merchandise_sales
    FROM months AS m
    LEFT JOIN monthly AS mo ON mo.purchase_month = m.month_start
)
SELECT f.month_start,
       f.delivered_orders,
       f.merchandise_sales                                                   AS merchandise_sales_brl,
       CAST(f.merchandise_sales / NULLIF(f.delivered_orders, 0) AS DECIMAL(18,2)) AS avg_order_value_brl,
       LAG(f.merchandise_sales) OVER (ORDER BY f.month_start)                AS previous_month_sales_brl,
       CAST(100.0 * (f.merchandise_sales - LAG(f.merchandise_sales) OVER (ORDER BY f.month_start))
            / NULLIF(LAG(f.merchandise_sales) OVER (ORDER BY f.month_start), 0) AS DECIMAL(18,2)) AS sales_growth_pct,
       SUM(f.merchandise_sales) OVER (ORDER BY f.month_start
                                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_sales_total_brl
FROM filled AS f
ORDER BY f.month_start
OPTION (MAXRECURSION 100);
GO

/* =====================================================================
   G3 - Which delivered orders have missing review or payment records?
   PURPOSE : monthly review coverage and payment coverage of delivered
             orders. The two measures are SEPARATE; an order can miss both.
   INPUT   : dbo.vw_delivered_orders (grain: order)
             dbo.order_reviews       (EXISTS / NOT EXISTS, valid score 1-5)
             derived table of payments summarised by order (LEFT JOIN)
   OUTPUT  : G3.1 monthly summary | G3.2 sample of delivered orders with no
             valid review | G3.3 sample with no payment record
   SQL     : EXISTS, NOT EXISTS, LEFT JOIN to a derived table.
             (Flags are computed in a CTE because SQL Server does not allow
             SUM(CASE WHEN EXISTS ...) directly.)
   DENOMINATOR: delivered orders of that month.
   Expected: totals 96,211 delivered | 95,568 with review | 643 without |
             96,211 with payment | 0 without payment | 0 missing both.
             G3.3 is expected to return 0 rows (every delivered order has a
             payment record) - an empty sample is a valid result.
   ===================================================================== */
-- G3.1 monthly coverage
WITH order_flags AS (                                -- grain: one row per delivered order
    SELECT d.order_id,
           d.purchase_month,
           CASE WHEN EXISTS (SELECT 1
                             FROM dbo.order_reviews AS r
                             WHERE r.order_id = d.order_id
                               AND r.review_score BETWEEN 1 AND 5) THEN 1 ELSE 0 END AS has_valid_review,
           CASE WHEN p.order_id IS NOT NULL THEN 1 ELSE 0 END                         AS has_payment_record
    FROM dbo.vw_delivered_orders AS d
    LEFT JOIN (SELECT order_id,                      -- derived table, grain: one row per order
                      COUNT(*)           AS payment_records,
                      SUM(payment_value) AS payment_total
               FROM dbo.order_payments
               GROUP BY order_id) AS p
           ON p.order_id = d.order_id
)
SELECT f.purchase_month,
       COUNT(*)                                            AS delivered_orders,
       SUM(f.has_valid_review)                             AS orders_with_valid_review,
       COUNT(*) - SUM(f.has_valid_review)                  AS orders_without_valid_review,
       CAST(100.0 * SUM(f.has_valid_review) / NULLIF(COUNT(*), 0) AS DECIMAL(6,2)) AS pct_with_review,
       SUM(f.has_payment_record)                           AS orders_with_payment,
       COUNT(*) - SUM(f.has_payment_record)                AS orders_without_payment,
       CAST(100.0 * SUM(f.has_payment_record) / NULLIF(COUNT(*), 0) AS DECIMAL(6,2)) AS pct_with_payment,
       SUM(CASE WHEN f.has_valid_review = 0 AND f.has_payment_record = 0 THEN 1 ELSE 0 END) AS orders_missing_both
FROM order_flags AS f
GROUP BY f.purchase_month
ORDER BY f.purchase_month;

-- G3.2 sample: delivered orders with NO valid review (NOT EXISTS)
SELECT TOP (10) d.order_id, d.purchase_month, 'no valid review' AS missing_item
FROM dbo.vw_delivered_orders AS d
WHERE NOT EXISTS (SELECT 1
                  FROM dbo.order_reviews AS r
                  WHERE r.order_id = d.order_id
                    AND r.review_score BETWEEN 1 AND 5)
ORDER BY d.order_id;

-- G3.3 sample: delivered orders with NO payment record (NOT EXISTS) - expected 0 rows
SELECT TOP (10) d.order_id, d.purchase_month, 'no payment record' AS missing_item
FROM dbo.vw_delivered_orders AS d
WHERE NOT EXISTS (SELECT 1
                  FROM dbo.order_payments AS pay
                  WHERE pay.order_id = d.order_id)
ORDER BY d.order_id;
GO

/* #####################################################################
   TRACK C - CUSTOMER BEHAVIOR
   People are identified by customer_unique_id (PDF rule). Population:
   delivered orders purchased in the window, unless a question says otherwise.
   ##################################################################### */

/* ---------------------------------------------------------------------
   TRACK C SUPPORT VIEW: dbo.vw_customer_summary
   GRAIN   : one row per PERSON (customer_unique_id)
   SOURCE  : dbo.vw_delivered_orders JOIN dbo.vw_order_values
             (both have one row per delivered order, so there is no fan-out)
   COLUMNS : delivered_orders  = DISTINCT delivered orders of the person
             total_spend       = SUM of the orders' merchandise value (BRL, no freight)
             avg_order_value   = total_spend / delivered_orders
             first_order_ts / last_order_ts = first and last purchase time
   --------------------------------------------------------------------- */
GO
CREATE OR ALTER VIEW dbo.vw_customer_summary AS
SELECT d.customer_unique_id,
       COUNT(DISTINCT d.order_id)                                   AS delivered_orders,
       SUM(v.merchandise_value)                                     AS total_spend,
       CAST(SUM(v.merchandise_value)
            / NULLIF(COUNT(DISTINCT d.order_id), 0) AS DECIMAL(18,2)) AS avg_order_value,
       MIN(d.purchase_ts)                                           AS first_order_ts,
       MAX(d.purchase_ts)                                           AS last_order_ts
FROM dbo.vw_delivered_orders AS d
JOIN dbo.vw_order_values     AS v ON v.order_id = d.order_id
GROUP BY d.customer_unique_id;
GO

/* =====================================================================
   C1 - How much do different customers spend?
   PURPOSE : describe spending per person and split people into value groups,
             to see how concentrated sales are.
   INPUT   : dbo.vw_customer_summary (grain: person)
   OUTPUT  : C1.0 the cut-points | C1.1 one row per value group |
             C1.2 the 20 highest-spending customers
   GROUPS  : percentile cut-points of total_spend (PERCENTILE_CONT):
               A. Lower   : below the median (P50)
               B. Middle  : P50 up to P90
               C. High    : P90 up to P99
               D. Top 1%  : P99 and above
   WHY PERCENTILES, NOT NTILE: spend is skewed (mean > median) and many
             people spend exactly the same amount (e.g. 1,574 people spent
             exactly 59.90). NTILE would put identical people into different
             groups arbitrarily. Comparing with percentile cut-points keeps
             equal spenders together, so group sizes are only approximately
             50/40/9/1 percent.
   DENOMINATORS: customer share = group customers / ALL 93,104 people;
             sales share = group sales / ALL delivered merchandise sales.
   SQL     : CTEs, PERCENTILE_CONT as an aggregate window, SUM() OVER () for
             shares, and RANK() (ranking function) in C1.2.
   Expected C1.0: P50 89.70 | P90 279.99 | P99 1,004.99
   Expected C1.1 (customers | % | orders | sales | sales % | avg spend):
       A. Lower  46,519 | 49.96 | 46,997 |  2,196,978.46 | 16.67 |   47.23
       B. Middle 37,267 | 40.03 | 38,889 |  5,564,596.01 | 42.22 |  149.32
       C. High    8,383 |  9.00 |  9,307 |  3,902,908.84 | 29.61 |  465.57
       D. Top 1%    935 |  1.00 |  1,018 |  1,516,543.82 | 11.51 | 1,621.97
       totals: 93,104 people | 96,211 orders | 13,181,027.13 BRL
   Expected C1.2: highest spender 13,440.00 BRL
   ===================================================================== */
-- C1.0 cut-points used for the groups
SELECT DISTINCT
       CAST(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY total_spend) OVER () AS DECIMAL(18,2)) AS p50_cutoff_brl,
       CAST(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY total_spend) OVER () AS DECIMAL(18,2)) AS p90_cutoff_brl,
       CAST(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_spend) OVER () AS DECIMAL(18,2)) AS p99_cutoff_brl
FROM dbo.vw_customer_summary;

-- C1.1 value groups
WITH with_cutoffs AS (                                  -- grain: one row per person
    SELECT cs.customer_unique_id,
           cs.delivered_orders,
           cs.total_spend,
           PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY cs.total_spend) OVER () AS p50,
           PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY cs.total_spend) OVER () AS p90,
           PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY cs.total_spend) OVER () AS p99
    FROM dbo.vw_customer_summary AS cs
),
grouped AS (                                            -- grain: one row per person, with its group
    SELECT c.*,
           CASE WHEN c.total_spend >= c.p99 THEN 'D. Top 1%'
                WHEN c.total_spend >= c.p90 THEN 'C. High (P90-P99)'
                WHEN c.total_spend >= c.p50 THEN 'B. Middle (P50-P90)'
                ELSE                             'A. Lower (below P50)' END AS value_group
    FROM with_cutoffs AS c
)
SELECT g.value_group,
       COUNT(*)                                                    AS customers,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(6,2)) AS pct_of_customers,
       SUM(g.delivered_orders)                                     AS delivered_orders,
       SUM(g.total_spend)                                          AS merchandise_sales_brl,
       CAST(100.0 * SUM(g.total_spend) / SUM(SUM(g.total_spend)) OVER () AS DECIMAL(6,2)) AS sales_share_pct,
       CAST(SUM(g.total_spend) / NULLIF(COUNT(*), 0)               AS DECIMAL(18,2)) AS avg_spend_per_customer_brl,
       CAST(SUM(g.total_spend) / NULLIF(SUM(g.delivered_orders), 0) AS DECIMAL(18,2)) AS avg_order_value_brl,
       MIN(g.total_spend)                                          AS min_spend_brl,
       MAX(g.total_spend)                                          AS max_spend_brl
FROM grouped AS g
GROUP BY g.value_group
ORDER BY g.value_group;

-- C1.2 the 20 highest-spending people (RANK: equal spenders share a rank)
SELECT TOP (20)
       RANK() OVER (ORDER BY cs.total_spend DESC) AS spend_rank,
       cs.customer_unique_id,
       cs.delivered_orders,
       cs.total_spend      AS total_spend_brl,
       cs.avg_order_value  AS avg_order_value_brl
FROM dbo.vw_customer_summary AS cs
ORDER BY cs.total_spend DESC, cs.customer_unique_id;
GO

/* =====================================================================
   C2 - How many customers purchase more than once?
   PURPOSE : size of observed repeat purchasing and the time between
             consecutive purchases of the same person.
   INPUT   : dbo.vw_delivered_orders (grain: order) and dbo.vw_customer_summary
             (grain: person). People = customer_unique_id.
   OUTPUT  : C2.1 summary row | C2.2 orders-per-person distribution |
             C2.3 gap summary | C2.4 gap bands
   DEFINITIONS (PDF Section 8):
             Observed repeat purchase = people with >= 2 delivered orders in
             the window / people with >= 1. It describes OBSERVED repetition
             only, not lifetime retention and not churn.
             Order sequence = ROW_NUMBER() per person ordered by purchase time,
             then order_id as a tie-breaker (265 people have two orders with the
             identical purchase timestamp).
             Gap (days) = (purchase time - previous purchase time of the same
             person) in SECONDS / 86400.0, so it can be fractional.
   SENSITIVITY: some "repeat" people placed several orders at the same moment
             (probably one basket split in several orders). C2.1 therefore also
             shows people with purchases on at least 2 different calendar days.
   SQL     : ROW_NUMBER() and LAG() window functions in a CTE; derived table.
   DENOMINATOR (C2.1): all 93,104 people with >= 1 delivered order.
   Expected C2.1 : people 93,104 | single 90,315 | repeat 2,789 | repeat share 3.00% |
                   people with >= 2 purchase days 2,005 (2.15%)
   Expected C2.2 : 1 order 90,315 | 2: 2,562 | 3: 180 | 4: 28 | 5: 9 | 6: 5 | 7: 3 | 9: 1 | 15: 1
   Expected C2.3 : 3,107 consecutive pairs | average gap 78.20 days | median 29.37 |
                   min 0.00 | max 582.86 | same-timestamp pairs 267 | pairs < 1 day 919 |
                   average gap excluding same-timestamp pairs 85.55 (2,840 pairs)
   Expected C2.4 : same timestamp 267 | >0 and <1 day 652 | 1-29 days 641 |
                   30-89 days 584 | 90-179 days 457 | 180+ days 506
   ===================================================================== */
-- C2.1 single vs repeat buyers
SELECT COUNT(*)                                              AS people_with_delivered_order,
       SUM(CASE WHEN p.delivered_orders = 1  THEN 1 ELSE 0 END) AS single_order_buyers,
       SUM(CASE WHEN p.delivered_orders >= 2 THEN 1 ELSE 0 END) AS repeat_buyers,
       CAST(100.0 * SUM(CASE WHEN p.delivered_orders >= 2 THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0) AS DECIMAL(6,2))               AS repeat_share_pct,
       SUM(CASE WHEN p.purchase_days >= 2 THEN 1 ELSE 0 END)     AS people_with_2plus_purchase_days,
       CAST(100.0 * SUM(CASE WHEN p.purchase_days >= 2 THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0) AS DECIMAL(6,2))               AS pct_with_2plus_purchase_days
FROM (SELECT customer_unique_id,                                 -- derived table, grain: one row per person
             COUNT(DISTINCT order_id)      AS delivered_orders,
             COUNT(DISTINCT purchase_date) AS purchase_days
      FROM dbo.vw_delivered_orders
      GROUP BY customer_unique_id) AS p;

-- C2.2 how many people placed 1, 2, 3 ... delivered orders
SELECT cs.delivered_orders AS orders_per_person,
       COUNT(*)            AS people,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(6,2)) AS pct_of_people
FROM dbo.vw_customer_summary AS cs
GROUP BY cs.delivered_orders
ORDER BY cs.delivered_orders;

-- C2.3 and C2.4 gaps between consecutive purchases
WITH ordered AS (                                   -- grain: one row per delivered order
    SELECT d.customer_unique_id,
           d.order_id,
           d.purchase_ts,
           ROW_NUMBER() OVER (PARTITION BY d.customer_unique_id
                              ORDER BY d.purchase_ts, d.order_id) AS order_seq,
           LAG(d.purchase_ts) OVER (PARTITION BY d.customer_unique_id
                                    ORDER BY d.purchase_ts, d.order_id) AS prev_purchase_ts
    FROM dbo.vw_delivered_orders AS d
),
gaps AS (                                           -- grain: one row per pair of consecutive orders
    SELECT o.customer_unique_id,
           o.order_seq,
           CAST(DATEDIFF(SECOND, o.prev_purchase_ts, o.purchase_ts) / 86400.0 AS DECIMAL(18,6)) AS gap_days
    FROM ordered AS o
    WHERE o.prev_purchase_ts IS NOT NULL
)
-- C2.3 summary of the gaps
SELECT COUNT(*)                                                AS consecutive_pairs,
       CAST(AVG(g.gap_days) AS DECIMAL(10,2))                  AS avg_gap_days,
       (SELECT DISTINCT CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY g2.gap_days) OVER () AS DECIMAL(10,2))
        FROM gaps AS g2)                                       AS median_gap_days,
       CAST(MIN(g.gap_days) AS DECIMAL(10,2))                  AS min_gap_days,
       CAST(MAX(g.gap_days) AS DECIMAL(10,2))                  AS max_gap_days,
       SUM(CASE WHEN g.gap_days = 0 THEN 1 ELSE 0 END)         AS same_timestamp_pairs,
       SUM(CASE WHEN g.gap_days < 1 THEN 1 ELSE 0 END)         AS pairs_under_1_day,
       CAST(AVG(CASE WHEN g.gap_days > 0 THEN g.gap_days END) AS DECIMAL(10,2)) AS avg_gap_days_excl_same_timestamp,
       SUM(CASE WHEN g.gap_days > 0 THEN 1 ELSE 0 END)         AS pairs_excl_same_timestamp
FROM gaps AS g;
GO

WITH ordered AS (
    SELECT d.customer_unique_id,
           d.purchase_ts,
           LAG(d.purchase_ts) OVER (PARTITION BY d.customer_unique_id
                                    ORDER BY d.purchase_ts, d.order_id) AS prev_purchase_ts
    FROM dbo.vw_delivered_orders AS d
),
gaps AS (
    SELECT CAST(DATEDIFF(SECOND, o.prev_purchase_ts, o.purchase_ts) / 86400.0 AS DECIMAL(18,6)) AS gap_days
    FROM ordered AS o
    WHERE o.prev_purchase_ts IS NOT NULL
),
banded AS (
    SELECT CASE WHEN g.gap_days = 0   THEN '1. same timestamp'
                WHEN g.gap_days < 1   THEN '2. under 1 day'
                WHEN g.gap_days < 30  THEN '3. 1-29 days'
                WHEN g.gap_days < 90  THEN '4. 30-89 days'
                WHEN g.gap_days < 180 THEN '5. 90-179 days'
                ELSE                       '6. 180+ days' END AS gap_band
    FROM gaps AS g
)
-- C2.4 gap bands
SELECT b.gap_band,
       COUNT(*) AS consecutive_pairs,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(6,2)) AS pct_of_pairs
FROM banded AS b
GROUP BY b.gap_band
ORDER BY b.gap_band;
GO

/* =====================================================================
   C3 - Which customers spend more than their state average?
   PURPOSE : compare each person's total spend with the average of people
             in the same state, to see who is above their local norm.
   INPUT   : dbo.vw_customer_summary (grain: person) and
             dbo.vw_delivered_orders (grain: order)
   STATE   : each person is assigned the state of their MOST RECENT delivered
             order in the window (latest purchase_ts, then greatest order_id).
             36 people bought from more than one state; they count once, in
             that last state.
   PEER AVERAGE : average total_spend of ALL people assigned to the state,
             including the person being compared (a state average).
   OUTPUT  : C3.0 check | C3.1 one row per state | C3.2 the 20 largest gaps
   SQL     : CORRELATED SUBQUERY - the subquery in the SELECT list refers to
             the current outer row (p.assigned_state = s.assigned_state).
             The people-level result is first stored in a temporary table with
             an index on the state, so the correlated lookup is fast.
             ROW_NUMBER() picks the most recent order; CTE.
   DENOMINATOR (C3.1 percent): people assigned to that state.
   Expected C3.0 : 93,104 people | 27 states
   Expected C3.1 : SP 39,059 people | avg 129.48 | above 11,599 (29.70%)
                   RJ 11,877 | 147.46 | 3,488 (29.37%)   MG 10,963 | 141.20 | 3,171 (28.92%)
                   RR 39 | 179.94 | 13 (33.33%)   AP 66 | 202.65 | 16 (24.24%)
                   all states together: 27,061 people above (29.07%), 0 exactly equal
   Expected C3.2 : #1 13,440.00 BRL, RJ, state avg 147.46, difference +13,292.54
                   #2 7,388.00 (RJ) | #3 7,160.00 (ES)
   Limitation: in this skewed distribution (mean > median) fewer than half
             of the people are above the state average; the average is pulled
             up by a few large spenders. States with few people (RR 39) give
             less stable averages.
   ===================================================================== */
IF OBJECT_ID('tempdb..#customer_state_spend') IS NOT NULL DROP TABLE #customer_state_spend;
IF OBJECT_ID('tempdb..#c3') IS NOT NULL DROP TABLE #c3;

WITH ranked_orders AS (                              -- grain: one row per delivered order
    SELECT d.customer_unique_id,
           d.customer_state,
           ROW_NUMBER() OVER (PARTITION BY d.customer_unique_id
                              ORDER BY d.purchase_ts DESC, d.order_id DESC) AS recency_rank
    FROM dbo.vw_delivered_orders AS d
)
SELECT cs.customer_unique_id,                        -- grain: one row per person
       r.customer_state AS assigned_state,
       cs.total_spend,
       cs.delivered_orders
INTO #customer_state_spend
FROM dbo.vw_customer_summary AS cs
JOIN ranked_orders           AS r
  ON r.customer_unique_id = cs.customer_unique_id
 AND r.recency_rank = 1;

CREATE CLUSTERED INDEX IX_customer_state_spend ON #customer_state_spend (assigned_state);

SELECT s.customer_unique_id,
       s.assigned_state,
       s.total_spend,
       (SELECT AVG(p.total_spend)                    -- correlated subquery: peers in the SAME state
        FROM #customer_state_spend AS p
        WHERE p.assigned_state = s.assigned_state) AS state_avg_spend,
       (SELECT COUNT(*)
        FROM #customer_state_spend AS p
        WHERE p.assigned_state = s.assigned_state) AS peer_customers
INTO #c3
FROM #customer_state_spend AS s;

-- C3.0 check
SELECT COUNT(*) AS people, COUNT(DISTINCT assigned_state) AS states
FROM #c3;

-- C3.1 state summary
SELECT c.assigned_state,
       COUNT(*)                                                       AS customers,
       CAST(MAX(c.state_avg_spend) AS DECIMAL(18,2))                  AS state_avg_spend_brl,
       SUM(CASE WHEN c.total_spend > c.state_avg_spend THEN 1 ELSE 0 END) AS customers_above_state_avg,
       CAST(100.0 * SUM(CASE WHEN c.total_spend > c.state_avg_spend THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0) AS DECIMAL(6,2))                    AS pct_above_state_avg,
       CASE WHEN COUNT(*) < 30 THEN 'small group (<30)' ELSE 'ok' END AS sample_flag
FROM #c3 AS c
GROUP BY c.assigned_state
ORDER BY customers DESC, c.assigned_state;

-- C3.2 the 20 people furthest above their state average
SELECT TOP (20)
       c.customer_unique_id,
       c.assigned_state,
       c.total_spend                                          AS total_spend_brl,
       CAST(c.state_avg_spend AS DECIMAL(18,2))               AS state_avg_spend_brl,
       CAST(c.total_spend - c.state_avg_spend AS DECIMAL(18,2)) AS difference_brl,
       c.peer_customers
FROM #c3 AS c
WHERE c.total_spend > c.state_avg_spend
ORDER BY c.total_spend - c.state_avg_spend DESC, c.customer_unique_id;
GO

/* =====================================================================
   C4 - Who purchases from popular categories?
   PURPOSE : compare people who bought from the three most popular categories
             with all other buyers (spend, repeat purchase).
   INPUT   : dbo.vw_order_items (grain: item row of a delivered order, with
             category_name) and dbo.vw_customer_summary (grain: person).
   POPULAR : the 3 categories with the most DISTINCT PEOPLE (customer_unique_id).
   SEGMENT : "Buyers of the top-3 categories" = people with at least one item in
             one of these categories. "All other buyers" = every other person.
             The two segments do not overlap and together contain all 93,104 people.
             Spend is the person's TOTAL spend (all categories).
   OUTPUT  : C4.0 the five most popular categories | C4.1 comparison of segments
   SQL     : MULTI-ROW SUBQUERIES: IN (SELECT person ...) which itself contains
             IN (SELECT TOP (3) category ...). CTE, SUM() OVER ().
   DENOMINATOR: customers in the segment (repeat share = people with >= 2
             delivered orders / people in the segment).
   Expected C4.0 : bed_bath_table 9,003 | health_beauty 8,462 | sports_leisure 7,324 |
                   computers_accessories 6,393 | furniture_decor 6,130
   Expected C4.1 : top-3 buyers  24,703 | spend 3,317,486.20 | per customer 134.29 | repeat 1,235 (5.00%) | 1.06 orders
                   other buyers  68,401 | spend 9,863,540.93 | per customer 144.20 | repeat 1,554 (2.27%) | 1.02 orders
   Limitation: a person can buy from other categories too; the segments describe
             exposure to popular categories, not a preference. The popular
             categories are popular partly because they are large.
   ===================================================================== */
-- C4.0
SELECT TOP (5)
       oi.category_name,
       COUNT(DISTINCT oi.customer_unique_id) AS buyers,
       COUNT(DISTINCT oi.order_id)           AS orders
FROM dbo.vw_order_items AS oi
GROUP BY oi.category_name
ORDER BY buyers DESC, oi.category_name;

-- C4.1
WITH segmented AS (                                  -- grain: one row per person
    SELECT cs.customer_unique_id,
           cs.delivered_orders,
           cs.total_spend,
           CASE WHEN cs.customer_unique_id IN (       -- multi-row subquery (people)
                         SELECT oi.customer_unique_id
                         FROM dbo.vw_order_items AS oi
                         WHERE oi.category_name IN (  -- multi-row subquery (3 categories)
                                   SELECT TOP (3) t.category_name
                                   FROM (SELECT category_name,
                                                COUNT(DISTINCT customer_unique_id) AS buyers
                                         FROM dbo.vw_order_items
                                         GROUP BY category_name) AS t
                                   ORDER BY t.buyers DESC, t.category_name))
                THEN '1. Buyers of the top-3 categories'
                ELSE '2. All other buyers' END AS segment
    FROM dbo.vw_customer_summary AS cs
)
SELECT s.segment,
       COUNT(*)                                                         AS customers,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(6,2))   AS pct_of_customers,
       SUM(s.total_spend)                                               AS merchandise_sales_brl,
       CAST(SUM(s.total_spend) / NULLIF(COUNT(*), 0) AS DECIMAL(18,2))  AS spend_per_customer_brl,
       CAST(1.0 * SUM(s.delivered_orders) / NULLIF(COUNT(*), 0) AS DECIMAL(10,3)) AS avg_orders_per_customer,
       SUM(CASE WHEN s.delivered_orders >= 2 THEN 1 ELSE 0 END)         AS repeat_buyers,
       CAST(100.0 * SUM(CASE WHEN s.delivered_orders >= 2 THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0) AS DECIMAL(6,2))                      AS repeat_share_pct
FROM segmented AS s
GROUP BY s.segment
ORDER BY s.segment;
GO

/* =====================================================================
   C5 - Which customers bought category X but not category Y?
   PURPOSE : compare people who bought X without Y with people who bought both.
   CHOICE  : X = bed_bath_table, Y = health_beauty - the two categories with
             the most delivered orders (9,267 and 8,610), so both have
             substantial volume. They are set in the two variables below.
   INPUT   : dbo.vw_customer_summary (grain: person), dbo.vw_order_items
   OUTPUT  : C5.0 volume of the two categories | C5.1 the two segments
   SQL     : EXISTS (bought X) and NOT EXISTS (did not buy Y); EXISTS for "both".
   DENOMINATOR: people in the segment.
   Expected C5.0 : bed_bath_table 9,267 orders / 9,003 people |
                   health_beauty  8,610 orders / 8,462 people
   Expected C5.1 : X not Y : 8,975 people | spend 1,081,330.36 | per person 120.48 |
                             1.072 orders | repeat 6.24%
                   X and Y :    28 people | spend     6,637.87 | per person 237.07 |
                             1.857 orders | repeat 64.29%
   Meaning of absence: "did not buy Y" only means no delivered Y item in this
             window of this snapshot. The person may have bought Y elsewhere or
             later, or never wanted it. Only 28 people bought both, so that
             segment is too small for firm conclusions.
   ===================================================================== */
DECLARE @cat_x VARCHAR(64) = 'bed_bath_table';
DECLARE @cat_y VARCHAR(64) = 'health_beauty';

-- C5.0
SELECT oi.category_name,
       COUNT(DISTINCT oi.order_id)           AS orders,
       COUNT(DISTINCT oi.customer_unique_id) AS people
FROM dbo.vw_order_items AS oi
WHERE oi.category_name IN (@cat_x, @cat_y)
GROUP BY oi.category_name
ORDER BY orders DESC;

-- C5.1
SELECT '1. Bought X, did NOT buy Y' AS segment,
       COUNT(*)                                                   AS people,
       SUM(cs.total_spend)                                        AS merchandise_sales_brl,
       CAST(SUM(cs.total_spend) / NULLIF(COUNT(*), 0) AS DECIMAL(18,2)) AS spend_per_person_brl,
       CAST(1.0 * SUM(cs.delivered_orders) / NULLIF(COUNT(*), 0) AS DECIMAL(10,3)) AS avg_orders_per_person,
       CAST(100.0 * SUM(CASE WHEN cs.delivered_orders >= 2 THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0) AS DECIMAL(6,2))                AS repeat_share_pct
FROM dbo.vw_customer_summary AS cs
WHERE EXISTS (SELECT 1 FROM dbo.vw_order_items AS x
              WHERE x.customer_unique_id = cs.customer_unique_id AND x.category_name = @cat_x)
  AND NOT EXISTS (SELECT 1 FROM dbo.vw_order_items AS y
                  WHERE y.customer_unique_id = cs.customer_unique_id AND y.category_name = @cat_y)
UNION ALL
SELECT '2. Bought BOTH X and Y',
       COUNT(*),
       SUM(cs.total_spend),
       CAST(SUM(cs.total_spend) / NULLIF(COUNT(*), 0) AS DECIMAL(18,2)),
       CAST(1.0 * SUM(cs.delivered_orders) / NULLIF(COUNT(*), 0) AS DECIMAL(10,3)),
       CAST(100.0 * SUM(CASE WHEN cs.delivered_orders >= 2 THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0) AS DECIMAL(6,2))
FROM dbo.vw_customer_summary AS cs
WHERE EXISTS (SELECT 1 FROM dbo.vw_order_items AS x
              WHERE x.customer_unique_id = cs.customer_unique_id AND x.category_name = @cat_x)
  AND EXISTS (SELECT 1 FROM dbo.vw_order_items AS y
              WHERE y.customer_unique_id = cs.customer_unique_id AND y.category_name = @cat_y)
ORDER BY segment;
GO

/* =====================================================================
   C6 - How do the first two purchases compare?
   PURPOSE : for people with at least 2 delivered orders, compare the value of
             the first and the second order and the time between them.
   INPUT   : dbo.vw_delivered_orders JOIN dbo.vw_order_values (grain: order)
   POPULATION: the 2,789 repeat customers (>= 2 delivered orders in the window).
   ORDER SEQUENCE: ROW_NUMBER() per person by purchase time, then order_id.
   OUTPUT  : C6.1 summary | C6.2 same summary without same-timestamp pairs |
             C6.3 a 10-row sample
   SQL     : ROW_NUMBER() and a SELF-JOIN of the sequenced orders
             (order_seq = 1 joined to order_seq = 2 of the same person); CTE.
   DENOMINATOR: repeat customers (one pair per person).
   Expected C6.1 : 2,789 pairs | avg first 123.28 | avg second 122.85 | avg difference -0.44 |
                   avg gap 80.22 days | median gap 28.98 |
                   second larger 1,272 (45.61%) | equal 317 | smaller 1,200 |
                   same-timestamp pairs 253 | pairs under 1 day 850
   Expected C6.2 : 2,536 pairs | avg gap 88.23 days | second larger 46.18%
   Limitation: 253 pairs have both orders at the same moment (probably a basket
             split in two orders); C6.2 shows the result without them. The
             second order of a person is only the second order OBSERVED in this window.
   ===================================================================== */
IF OBJECT_ID('tempdb..#first_two') IS NOT NULL DROP TABLE #first_two;

WITH order_seq AS (                                  -- grain: one row per delivered order
    SELECT d.customer_unique_id,
           d.order_id,
           d.purchase_ts,
           v.merchandise_value AS order_value,
           ROW_NUMBER() OVER (PARTITION BY d.customer_unique_id
                              ORDER BY d.purchase_ts, d.order_id) AS order_seq
    FROM dbo.vw_delivered_orders AS d
    JOIN dbo.vw_order_values     AS v ON v.order_id = d.order_id
)
SELECT o1.customer_unique_id,                        -- grain: one row per repeat person
       o1.order_id        AS first_order_id,
       o2.order_id        AS second_order_id,
       o1.order_value     AS first_order_value,
       o2.order_value     AS second_order_value,
       CAST(DATEDIFF(SECOND, o1.purchase_ts, o2.purchase_ts) / 86400.0 AS DECIMAL(18,6)) AS gap_days
INTO #first_two
FROM order_seq AS o1
JOIN order_seq AS o2                                 -- self-join: 1st order with 2nd order of the same person
  ON o2.customer_unique_id = o1.customer_unique_id
 AND o1.order_seq = 1
 AND o2.order_seq = 2;

-- C6.1 summary
SELECT COUNT(*)                                                   AS repeat_customers,
       CAST(AVG(t.first_order_value)  AS DECIMAL(18,2))           AS avg_first_order_brl,
       CAST(AVG(t.second_order_value) AS DECIMAL(18,2))           AS avg_second_order_brl,
       CAST(AVG(t.second_order_value - t.first_order_value) AS DECIMAL(18,2)) AS avg_difference_brl,
       CAST(AVG(t.gap_days) AS DECIMAL(10,2))                     AS avg_gap_days,
       (SELECT DISTINCT CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY t2.gap_days) OVER () AS DECIMAL(10,2))
        FROM #first_two AS t2)                                    AS median_gap_days,
       SUM(CASE WHEN t.second_order_value >  t.first_order_value THEN 1 ELSE 0 END) AS second_larger,
       SUM(CASE WHEN t.second_order_value =  t.first_order_value THEN 1 ELSE 0 END) AS second_equal,
       SUM(CASE WHEN t.second_order_value <  t.first_order_value THEN 1 ELSE 0 END) AS second_smaller,
       CAST(100.0 * SUM(CASE WHEN t.second_order_value > t.first_order_value THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0) AS DECIMAL(6,2))                AS pct_second_larger,
       SUM(CASE WHEN t.gap_days = 0 THEN 1 ELSE 0 END)            AS same_timestamp_pairs,
       SUM(CASE WHEN t.gap_days < 1 THEN 1 ELSE 0 END)            AS pairs_under_1_day
FROM #first_two AS t;

-- C6.2 sensitivity: without pairs whose two orders have the identical timestamp
SELECT COUNT(*)                                                   AS repeat_customers,
       CAST(AVG(t.gap_days) AS DECIMAL(10,2))                     AS avg_gap_days,
       CAST(100.0 * SUM(CASE WHEN t.second_order_value > t.first_order_value THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0) AS DECIMAL(6,2))                AS pct_second_larger
FROM #first_two AS t
WHERE t.gap_days > 0;

-- C6.3 sample of ten pairs
SELECT TOP (10) t.customer_unique_id, t.first_order_value, t.second_order_value,
       CAST(t.gap_days AS DECIMAL(10,2)) AS gap_days,
       CASE WHEN t.second_order_value > t.first_order_value THEN 'larger'
            WHEN t.second_order_value = t.first_order_value THEN 'equal' ELSE 'smaller' END AS second_vs_first
FROM #first_two AS t
ORDER BY t.customer_unique_id;
GO

/* =====================================================================
   C7 - Do single-order and repeat customers have different experiences?
   PURPOSE : compare delivery, ratings and review coverage of single-order
             and repeat customers.
   INPUT   : dbo.vw_delivered_orders (grain: order), dbo.vw_customer_summary,
             dbo.vw_order_review (ONE review per order) - joined with LEFT JOIN
             so orders without a review stay in the denominators.
   GROUPS  : Single-order customers = exactly 1 delivered order in the window;
             Repeat customers = 2 or more.
   BASES   : (a) ALL delivered orders of the group (repeat customers contribute
                 several orders)
             (b) FIRST delivered order of each person only, so both groups are
                 compared on the same kind of experience, the one BEFORE any
                 repeat purchase.
   DENOMINATORS (PDF Section 8), each shown next to its count:
             late rate        = late orders / orders with valid delivery dates
             low-rating rate  = low-rated orders (score 1-2) / orders with a valid review
             review coverage  = orders with a valid review / all delivered orders
             avg delivery days = purchase -> customer delivery, valid pairs only
   Expected (all orders):
       Repeat : 5,896 orders | valid dates 5,896 | avg 12.30 days | late 339 (5.75%) |
                reviewed 5,844 (99.12%) | avg score 4.216 | low 693 (11.86%)
       Single : 90,315 | 90,307 | 12.55 | late 6,192 (6.86%) |
                89,724 (99.35%) | 4.152 | 11,536 (12.86%)
   Expected (first order only):
       Repeat : 2,789 | 2,789 | 12.40 | late 160 (5.74%) | 2,768 (99.25%) | 4.199 | 334 (12.07%)
       Single : same as above (their only order is their first)
   Limitation: the observation window is short. A person counted as "single"
             may still buy again after August 2018, and people who first bought
             late in the window had little time to repeat. Differences are small
             and are associations, not causes.
   ===================================================================== */
IF OBJECT_ID('tempdb..#c7') IS NOT NULL DROP TABLE #c7;

SELECT d.order_id,                                   -- grain: one row per delivered order
       d.customer_unique_id,
       CASE WHEN cs.delivered_orders >= 2 THEN 'Repeat customers' ELSE 'Single-order customers' END AS customer_group,
       ROW_NUMBER() OVER (PARTITION BY d.customer_unique_id
                          ORDER BY d.purchase_ts, d.order_id) AS order_seq,
       d.has_valid_delivery_dates,
       d.delivery_days,
       d.is_late,
       r.review_score,
       r.is_low_rating
INTO #c7
FROM dbo.vw_delivered_orders AS d
JOIN dbo.vw_customer_summary AS cs ON cs.customer_unique_id = d.customer_unique_id
LEFT JOIN dbo.vw_order_review AS r ON r.order_id = d.order_id;

SELECT x.basis,
       x.customer_group,
       COUNT(*)                                                    AS delivered_orders,
       SUM(x.has_valid_delivery_dates)                             AS orders_with_valid_dates,
       CAST(AVG(x.delivery_days) AS DECIMAL(10,2))                 AS avg_delivery_days,
       SUM(x.is_late)                                              AS late_orders,
       CAST(100.0 * SUM(x.is_late) / NULLIF(SUM(x.has_valid_delivery_dates), 0) AS DECIMAL(6,2)) AS late_rate_pct,
       COUNT(x.review_score)                                       AS reviewed_orders,
       CAST(100.0 * COUNT(x.review_score) / NULLIF(COUNT(*), 0) AS DECIMAL(6,2)) AS review_coverage_pct,
       CAST(AVG(CAST(x.review_score AS DECIMAL(10,4))) AS DECIMAL(10,3)) AS avg_review_score,
       SUM(x.is_low_rating)                                        AS low_rated_orders,
       CAST(100.0 * SUM(x.is_low_rating) / NULLIF(COUNT(x.review_score), 0) AS DECIMAL(6,2)) AS low_rating_rate_pct
FROM (SELECT 'a. All delivered orders' AS basis, c.* FROM #c7 AS c
      UNION ALL
      SELECT 'b. First delivered order only', c.* FROM #c7 AS c WHERE c.order_seq = 1) AS x
GROUP BY x.basis, x.customer_group
ORDER BY x.basis, x.customer_group DESC;
GO

/* =====================================================================
   O1 - Does the observed repeat-purchase share depend on WHEN a person first bought?
   BUSINESS OBJECTIVE : the customer-insights team should not read the falling
             repeat share of recent months as a real decline. People who first
             bought in 2018 simply had less time left to buy again. This
             question separates "less time" from "less repetition".
   WHY IT MATTERS : avoids a wrong conclusion about customer loyalty; shows
             which cohorts can be compared fairly.
   TABLES/COLUMNS : dbo.vw_delivered_orders (customer_unique_id, order_id,
             purchase_ts)
   POPULATION: all 93,104 people with a delivered order; cohort = month of
             the FIRST delivered order.
   MEASURES  : repeat_share = people with a 2nd delivered order in the window / cohort people
             repeat_90d_share = people whose 2nd order came within 90 days of
             the first / people whose first order leaves a FULL 90-day window
             (first order + 90 days <= 2018-09-01). Only this second measure is
             comparable across cohorts.
   SQL CONCEPTS : ROW_NUMBER() inside a CTE, conditional aggregation, chained
             CTEs, DATEADD/DATEFROMPARTS.
   Expected : 20 cohorts | totals: 93,104 people | 2,789 repeat | 75,448 with a full
             90-day window | 1,717 repeated within 90 days
       2017-01: 718 people | 52 (7.24%) | full 718 | within 90d 26 (3.62%)
       2017-05: 3,451 | 182 (5.27%) | 3,451 | 98 (2.84%)
       2018-05: 6,508 | 109 (1.67%) | 6,508 | 105 (1.61%)
       2018-06: 5,879 | 70 (1.19%) | partial window: 316 people | 6 (1.90%)
       2018-07: 5,949 | 88 (1.48%) | no full window -> NULL
       2018-08: 6,144 | 34 (0.55%) | no full window -> NULL
   Interpretation guide: repeat_share falls steadily because later cohorts
             had less time; the 90-day share is flatter. Cohorts marked
             'partial' or 'none' should not be compared. Descriptive only.
   ===================================================================== */
WITH order_seq AS (                                  -- grain: one row per delivered order
    SELECT d.customer_unique_id,
           d.purchase_ts,
           ROW_NUMBER() OVER (PARTITION BY d.customer_unique_id
                              ORDER BY d.purchase_ts, d.order_id) AS order_seq
    FROM dbo.vw_delivered_orders AS d
),
person AS (                                          -- grain: one row per person
    SELECT o.customer_unique_id,
           MAX(CASE WHEN o.order_seq = 1 THEN o.purchase_ts END) AS first_ts,
           MAX(CASE WHEN o.order_seq = 2 THEN o.purchase_ts END) AS second_ts
    FROM order_seq AS o
    GROUP BY o.customer_unique_id
),
flags AS (                                           -- grain: one row per person, with flags
    SELECT p.customer_unique_id,
           DATEFROMPARTS(YEAR(p.first_ts), MONTH(p.first_ts), 1) AS cohort_month,
           CASE WHEN p.second_ts IS NOT NULL THEN 1 ELSE 0 END AS repeated,
           CASE WHEN DATEADD(DAY, 90, p.first_ts) <= '2018-09-01' THEN 1 ELSE 0 END AS full_90d_window,
           CASE WHEN DATEADD(DAY, 90, p.first_ts) <= '2018-09-01'
                 AND p.second_ts IS NOT NULL
                 AND p.second_ts <= DATEADD(DAY, 90, p.first_ts) THEN 1 ELSE 0 END AS repeated_within_90d
    FROM person AS p
)
SELECT f.cohort_month,
       COUNT(*)                                                       AS cohort_people,
       SUM(f.repeated)                                                AS repeat_people,
       CAST(100.0 * SUM(f.repeated) / NULLIF(COUNT(*), 0) AS DECIMAL(6,2)) AS repeat_share_pct,
       SUM(f.full_90d_window)                                         AS people_with_full_90d_window,
       SUM(f.repeated_within_90d)                                     AS repeated_within_90d,
       CAST(100.0 * SUM(f.repeated_within_90d) / NULLIF(SUM(f.full_90d_window), 0) AS DECIMAL(6,2)) AS repeat_90d_share_pct,
       CASE WHEN SUM(f.full_90d_window) = COUNT(*) THEN 'full'
            WHEN SUM(f.full_90d_window) = 0         THEN 'none'
            ELSE 'partial' END                                        AS window_90d
FROM flags AS f
GROUP BY f.cohort_month
ORDER BY f.cohort_month;
GO

/* =====================================================================
   O2 - When a customer buys again, is the second order in a category already bought?
   BUSINESS OBJECTIVE : see whether the second purchase deepens a category the
             person already bought (re-purchase) or opens new categories.
   WHY IT MATTERS : informs whether follow-up offers should repeat the first
             category or suggest new ones. Descriptive; it does not show why.
   TABLES/COLUMNS : dbo.vw_delivered_orders (order_id, purchase_ts,
             customer_unique_id), dbo.vw_order_items (order_id, category_name)
   POPULATION: the 2,789 repeat customers; first two delivered orders only.
   MEASURE   : pairs where the second order contains at least one category
             that the first order also contained / pairs with a KNOWN category
             in BOTH orders. The category 'unknown' (missing category) is not
             used for matching, and 65 pairs without a known category in one of
             the two orders are counted separately.
   SENSITIVITY: pairs whose two orders have the identical timestamp are shown
             separately, because they are probably one basket split in two.
   SQL CONCEPTS : EXISTS nested inside EXISTS (correlated), ROW_NUMBER + self-join
             in CTEs, GROUP BY ROLLUP with GROUPING().
   Expected : all pairs 2,789 | known 2,724 | repeating a category 1,294 |
                          only new categories 1,430 | 47.50%
              same timestamp 253 | known 246 | repeating 165 | new 81 | 67.07%
              later          2,536 | known 2,478 | repeating 1,129 | new 1,349 | 45.56%
   ===================================================================== */
WITH order_seq AS (                                  -- grain: one row per delivered order
    SELECT d.customer_unique_id, d.order_id, d.purchase_ts,
           ROW_NUMBER() OVER (PARTITION BY d.customer_unique_id
                              ORDER BY d.purchase_ts, d.order_id) AS order_seq
    FROM dbo.vw_delivered_orders AS d
),
pairs AS (                                           -- grain: one row per repeat person
    SELECT a.customer_unique_id,
           a.order_id AS first_order_id,
           b.order_id AS second_order_id,
           CASE WHEN a.purchase_ts = b.purchase_ts THEN 1 ELSE 0 END AS same_timestamp
    FROM order_seq AS a
    JOIN order_seq AS b
      ON b.customer_unique_id = a.customer_unique_id
     AND a.order_seq = 1
     AND b.order_seq = 2
),
flags AS (                                           -- grain: one row per repeat person, with flags
    SELECT p.*,
           CASE WHEN EXISTS (SELECT 1 FROM dbo.vw_order_items AS i1
                             WHERE i1.order_id = p.first_order_id  AND i1.category_name <> 'unknown')
                 AND EXISTS (SELECT 1 FROM dbo.vw_order_items AS i2
                             WHERE i2.order_id = p.second_order_id AND i2.category_name <> 'unknown')
                THEN 1 ELSE 0 END AS both_orders_known,
           CASE WHEN EXISTS (SELECT 1
                             FROM dbo.vw_order_items AS i2
                             WHERE i2.order_id = p.second_order_id
                               AND i2.category_name <> 'unknown'
                               AND EXISTS (SELECT 1                      -- same category in the first order
                                           FROM dbo.vw_order_items AS i1
                                           WHERE i1.order_id = p.first_order_id
                                             AND i1.category_name = i2.category_name))
                THEN 1 ELSE 0 END AS repeats_a_category
    FROM pairs AS p
)
SELECT CASE WHEN GROUPING(f.same_timestamp) = 1 THEN 'All pairs'
            WHEN f.same_timestamp = 1 THEN 'Both orders at the same timestamp'
            ELSE 'Second order later' END                              AS pair_type,
       COUNT(*)                                                        AS pairs_total,
       SUM(f.both_orders_known)                                        AS pairs_with_known_categories,
       SUM(CASE WHEN f.both_orders_known = 1 THEN f.repeats_a_category ELSE 0 END) AS pairs_repeating_a_category,
       SUM(f.both_orders_known)
         - SUM(CASE WHEN f.both_orders_known = 1 THEN f.repeats_a_category ELSE 0 END) AS pairs_only_new_categories,
       CAST(100.0 * SUM(CASE WHEN f.both_orders_known = 1 THEN f.repeats_a_category ELSE 0 END)
            / NULLIF(SUM(f.both_orders_known), 0) AS DECIMAL(6,2))     AS pct_repeating_a_category
FROM flags AS f
GROUP BY ROLLUP (f.same_timestamp)
ORDER BY GROUPING(f.same_timestamp) DESC, f.same_timestamp DESC;
GO
