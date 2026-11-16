/* =====================================================================
   FILE      : sql/04_dashboard_exports.sql
   PROJECT   : BI-Olist-Analytics  -  TRACK C (Customer behavior)
   PURPOSE   : Queries that produce the tables loaded into the Excel
               dashboard (sheet SQL_Results). Every result keeps the
               SUPPORTING SUMS AND COUNTS (numerators / denominators), so
               Excel can recompute rates after filtering and never
               averages percentages (PDF Section 8).
   RUN ORDER : 01_schema -> 02_validation -> 03_analysis -> 04_dashboard_exports
               (needs dbo.vw_customer_summary, which 03_analysis.sql creates)
   STATUS    : GENERATED CODE - NOT YET TESTED ON A REAL SQL SERVER.
   HOW TO EXPORT : run each block, then in SSMS right-click the result grid
               -> "Save Results As..." -> CSV (UTF-8, with headers), using the
               file name written in the header of the block (results/*.csv).
               Then paste the rows into the matching Excel Table.

   POPULATION : delivered orders purchased 2017-01-01 <= d < 2018-09-01.
   PEOPLE     : DISTINCT customer_unique_id.
   ===================================================================== */
USE OlistBI;
GO
SET NOCOUNT ON;
GO

/* =====================================================================
   EXP_01  kpi_overview.csv        (Dashboard KPI cards, questions G1/C1/C2)
   GRAIN   : one row (whole population)
   COLUMNS : delivered_orders, people, merchandise_sales_brl,
             repeat_people, single_people, repeat_orders
   Excel recomputes: repeat share = repeat_people / people
                     spend per customer = merchandise_sales_brl / people
                     AOV = merchandise_sales_brl / delivered_orders
   Expected: 96,211 | 93,104 | 13,181,027.13 | 2,789 | 90,315
   ===================================================================== */
SELECT (SELECT COUNT(*) FROM dbo.vw_delivered_orders)                  AS delivered_orders,
       COUNT(*)                                                        AS people,
       SUM(cs.total_spend)                                             AS merchandise_sales_brl,
       SUM(CASE WHEN cs.delivered_orders >= 2 THEN 1 ELSE 0 END)       AS repeat_people,
       SUM(CASE WHEN cs.delivered_orders  = 1 THEN 1 ELSE 0 END)       AS single_people
FROM dbo.vw_customer_summary AS cs;
GO

/* =====================================================================
   EXP_02  c1_value_groups.csv     (question C1)
   GRAIN   : one row per value group (4 rows)
   COLUMNS : value_group, customers, delivered_orders, merchandise_sales_brl
   Shares and averages are recomputed in Excel from these sums.
   ===================================================================== */
WITH with_cutoffs AS (
    SELECT cs.customer_unique_id, cs.delivered_orders, cs.total_spend,
           PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY cs.total_spend) OVER () AS p50,
           PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY cs.total_spend) OVER () AS p90,
           PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY cs.total_spend) OVER () AS p99
    FROM dbo.vw_customer_summary AS cs
),
grouped AS (
    SELECT c.*,
           CASE WHEN c.total_spend >= c.p99 THEN 'D. Top 1%'
                WHEN c.total_spend >= c.p90 THEN 'C. High (P90-P99)'
                WHEN c.total_spend >= c.p50 THEN 'B. Middle (P50-P90)'
                ELSE                             'A. Lower (below P50)' END AS value_group
    FROM with_cutoffs AS c
)
SELECT g.value_group,
       COUNT(*)                AS customers,
       SUM(g.delivered_orders) AS delivered_orders,
       SUM(g.total_spend)      AS merchandise_sales_brl
FROM grouped AS g
GROUP BY g.value_group
ORDER BY g.value_group;
GO

/* =====================================================================
   EXP_03  c2_orders_per_person.csv   (question C2)
   GRAIN   : one row per number of delivered orders per person
   ===================================================================== */
SELECT cs.delivered_orders AS orders_per_person,
       COUNT(*)            AS people
FROM dbo.vw_customer_summary AS cs
GROUP BY cs.delivered_orders
ORDER BY cs.delivered_orders;
GO

/* =====================================================================
   EXP_04  c2_gap_bands.csv        (question C2)
   GRAIN   : one row per gap band between consecutive purchases
   ===================================================================== */
WITH ordered AS (
    SELECT d.customer_unique_id, d.purchase_ts,
           LAG(d.purchase_ts) OVER (PARTITION BY d.customer_unique_id
                                    ORDER BY d.purchase_ts, d.order_id) AS prev_ts
    FROM dbo.vw_delivered_orders AS d
),
gaps AS (
    SELECT CAST(DATEDIFF(SECOND, o.prev_ts, o.purchase_ts) / 86400.0 AS DECIMAL(18,6)) AS gap_days
    FROM ordered AS o
    WHERE o.prev_ts IS NOT NULL
)
SELECT CASE WHEN g.gap_days = 0   THEN '1. same timestamp'
            WHEN g.gap_days < 1   THEN '2. under 1 day'
            WHEN g.gap_days < 30  THEN '3. 1-29 days'
            WHEN g.gap_days < 90  THEN '4. 30-89 days'
            WHEN g.gap_days < 180 THEN '5. 90-179 days'
            ELSE                       '6. 180+ days' END AS gap_band,
       COUNT(*)           AS consecutive_pairs
FROM gaps AS g
GROUP BY CASE WHEN g.gap_days = 0   THEN '1. same timestamp'
              WHEN g.gap_days < 1   THEN '2. under 1 day'
              WHEN g.gap_days < 30  THEN '3. 1-29 days'
              WHEN g.gap_days < 90  THEN '4. 30-89 days'
              WHEN g.gap_days < 180 THEN '5. 90-179 days'
              ELSE                       '6. 180+ days' END
ORDER BY gap_band;
GO

/* =====================================================================
   EXP_05  c3_state_summary.csv    (question C3)  - filter dimension: state
   GRAIN   : one row per assigned customer state (27 rows)
   COLUMNS : assigned_state, customers, total_spend_brl,
             customers_above_state_avg
   state average = total_spend_brl / customers (recomputed in Excel)
   ===================================================================== */
WITH ranked_orders AS (
    SELECT d.customer_unique_id, d.customer_state,
           ROW_NUMBER() OVER (PARTITION BY d.customer_unique_id
                              ORDER BY d.purchase_ts DESC, d.order_id DESC) AS recency_rank
    FROM dbo.vw_delivered_orders AS d
),
person_state AS (
    SELECT cs.customer_unique_id, r.customer_state AS assigned_state,
           cs.total_spend, cs.delivered_orders
    FROM dbo.vw_customer_summary AS cs
    JOIN ranked_orders AS r
      ON r.customer_unique_id = cs.customer_unique_id AND r.recency_rank = 1
),
with_avg AS (
    SELECT ps.*,
           AVG(ps.total_spend) OVER (PARTITION BY ps.assigned_state) AS state_avg
    FROM person_state AS ps
)
SELECT w.assigned_state,
       COUNT(*)                                                      AS customers,
       SUM(w.total_spend)                                            AS total_spend_brl,
       SUM(CASE WHEN w.total_spend > w.state_avg THEN 1 ELSE 0 END)  AS customers_above_state_avg,
       SUM(CASE WHEN w.delivered_orders >= 2 THEN 1 ELSE 0 END)      AS repeat_people
FROM with_avg AS w
GROUP BY w.assigned_state
ORDER BY customers DESC, w.assigned_state;
GO

/* =====================================================================
   EXP_06  c4_segments.csv         (question C4)
   GRAIN   : one row per segment (2 rows)
   COLUMNS : segment, customers, merchandise_sales_brl, repeat_people
   ===================================================================== */
WITH segmented AS (
    SELECT cs.customer_unique_id, cs.delivered_orders, cs.total_spend,
           CASE WHEN cs.customer_unique_id IN (
                         SELECT oi.customer_unique_id
                         FROM dbo.vw_order_items AS oi
                         WHERE oi.category_name IN (
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
       COUNT(*)                                                    AS customers,
       SUM(s.total_spend)                                          AS merchandise_sales_brl,
       SUM(CASE WHEN s.delivered_orders >= 2 THEN 1 ELSE 0 END)    AS repeat_people
FROM segmented AS s
GROUP BY s.segment
ORDER BY s.segment;
GO

/* =====================================================================
   EXP_07  c5_segments.csv         (question C5)   X = bed_bath_table, Y = health_beauty
   GRAIN   : one row per segment (2 rows)
   ===================================================================== */
DECLARE @cat_x VARCHAR(64) = 'bed_bath_table';
DECLARE @cat_y VARCHAR(64) = 'health_beauty';
SELECT '1. Bought X, did NOT buy Y' AS segment,
       COUNT(*) AS people, SUM(cs.total_spend) AS merchandise_sales_brl,
       SUM(CASE WHEN cs.delivered_orders >= 2 THEN 1 ELSE 0 END) AS repeat_people
FROM dbo.vw_customer_summary AS cs
WHERE EXISTS (SELECT 1 FROM dbo.vw_order_items AS x
              WHERE x.customer_unique_id = cs.customer_unique_id AND x.category_name = @cat_x)
  AND NOT EXISTS (SELECT 1 FROM dbo.vw_order_items AS y
                  WHERE y.customer_unique_id = cs.customer_unique_id AND y.category_name = @cat_y)
UNION ALL
SELECT '2. Bought BOTH X and Y',
       COUNT(*), SUM(cs.total_spend),
       SUM(CASE WHEN cs.delivered_orders >= 2 THEN 1 ELSE 0 END)
FROM dbo.vw_customer_summary AS cs
WHERE EXISTS (SELECT 1 FROM dbo.vw_order_items AS x
              WHERE x.customer_unique_id = cs.customer_unique_id AND x.category_name = @cat_x)
  AND EXISTS (SELECT 1 FROM dbo.vw_order_items AS y
              WHERE y.customer_unique_id = cs.customer_unique_id AND y.category_name = @cat_y)
ORDER BY segment;
GO

/* =====================================================================
   EXP_08  c6_first_two.csv        (question C6)
   GRAIN   : one row (repeat customers, 1 pair per person)
   COLUMNS : pairs, avg_first_order_brl, avg_second_order_brl, avg_gap_days,
             second_larger, second_equal, second_smaller, same_timestamp_pairs
   The averages describe ONE population (all pairs); they are not combined
   with other averages in Excel. Counts allow the share "second larger".
   ===================================================================== */
WITH order_seq AS (
    SELECT d.customer_unique_id, d.order_id, d.purchase_ts,
           v.merchandise_value AS order_value,
           ROW_NUMBER() OVER (PARTITION BY d.customer_unique_id
                              ORDER BY d.purchase_ts, d.order_id) AS order_seq
    FROM dbo.vw_delivered_orders AS d
    JOIN dbo.vw_order_values     AS v ON v.order_id = d.order_id
),
pairs AS (
    SELECT o1.order_value AS v1, o2.order_value AS v2,
           CAST(DATEDIFF(SECOND, o1.purchase_ts, o2.purchase_ts) / 86400.0 AS DECIMAL(18,6)) AS gap_days
    FROM order_seq AS o1
    JOIN order_seq AS o2
      ON o2.customer_unique_id = o1.customer_unique_id AND o1.order_seq = 1 AND o2.order_seq = 2
)
SELECT COUNT(*)                                          AS pairs,
       CAST(AVG(p.v1) AS DECIMAL(18,2))                  AS avg_first_order_brl,
       CAST(AVG(p.v2) AS DECIMAL(18,2))                  AS avg_second_order_brl,
       CAST(AVG(p.gap_days) AS DECIMAL(10,2))            AS avg_gap_days,
       SUM(CASE WHEN p.v2 >  p.v1 THEN 1 ELSE 0 END)     AS second_larger,
       SUM(CASE WHEN p.v2 =  p.v1 THEN 1 ELSE 0 END)     AS second_equal,
       SUM(CASE WHEN p.v2 <  p.v1 THEN 1 ELSE 0 END)     AS second_smaller,
       SUM(CASE WHEN p.gap_days = 0 THEN 1 ELSE 0 END)   AS same_timestamp_pairs
FROM pairs AS p;
GO

/* =====================================================================
   EXP_09  c7_experience.csv       (question C7)
   GRAIN   : one row per basis x customer group (4 rows)
   Excel recomputes late rate, review coverage and low-rating rate from the
   counts below. avg_delivery_days and avg_review_score are the averages of
   ONE group each (never averaged across groups).
   ===================================================================== */
WITH base AS (
    SELECT d.order_id,
           CASE WHEN cs.delivered_orders >= 2 THEN 'Repeat customers' ELSE 'Single-order customers' END AS customer_group,
           ROW_NUMBER() OVER (PARTITION BY d.customer_unique_id
                              ORDER BY d.purchase_ts, d.order_id) AS order_seq,
           d.has_valid_delivery_dates, d.delivery_days, d.is_late,
           r.review_score, r.is_low_rating
    FROM dbo.vw_delivered_orders AS d
    JOIN dbo.vw_customer_summary AS cs ON cs.customer_unique_id = d.customer_unique_id
    LEFT JOIN dbo.vw_order_review AS r ON r.order_id = d.order_id
)
SELECT x.basis, x.customer_group,
       COUNT(*)                                  AS delivered_orders,
       SUM(x.has_valid_delivery_dates)           AS orders_with_valid_dates,
       CAST(AVG(x.delivery_days) AS DECIMAL(10,2)) AS avg_delivery_days,
       SUM(x.is_late)                            AS late_orders,
       COUNT(x.review_score)                     AS reviewed_orders,
       CAST(AVG(CAST(x.review_score AS DECIMAL(10,4))) AS DECIMAL(10,3)) AS avg_review_score,
       SUM(x.is_low_rating)                      AS low_rated_orders
FROM (SELECT 'a. All delivered orders' AS basis, b.* FROM base AS b
      UNION ALL
      SELECT 'b. First delivered order only', b.* FROM base AS b WHERE b.order_seq = 1) AS x
GROUP BY x.basis, x.customer_group
ORDER BY x.basis, x.customer_group DESC;
GO

/* =====================================================================
   EXP_10  o1_cohorts.csv          (question O1)  - TIME TREND for the dashboard
   GRAIN   : one row per cohort month (month of the person's first delivered
             order) - 20 rows
   COLUMNS : cohort_month, cohort_people, repeat_people,
             people_with_full_90d_window, repeated_within_90d
   ===================================================================== */
WITH order_seq AS (
    SELECT d.customer_unique_id, d.purchase_ts,
           ROW_NUMBER() OVER (PARTITION BY d.customer_unique_id
                              ORDER BY d.purchase_ts, d.order_id) AS order_seq
    FROM dbo.vw_delivered_orders AS d
),
person AS (
    SELECT o.customer_unique_id,
           MAX(CASE WHEN o.order_seq = 1 THEN o.purchase_ts END) AS first_ts,
           MAX(CASE WHEN o.order_seq = 2 THEN o.purchase_ts END) AS second_ts
    FROM order_seq AS o
    GROUP BY o.customer_unique_id
),
flags AS (
    SELECT DATEFROMPARTS(YEAR(p.first_ts), MONTH(p.first_ts), 1) AS cohort_month,
           CASE WHEN p.second_ts IS NOT NULL THEN 1 ELSE 0 END AS repeated,
           CASE WHEN DATEADD(DAY, 90, p.first_ts) <= '2018-09-01' THEN 1 ELSE 0 END AS full_90d_window,
           CASE WHEN DATEADD(DAY, 90, p.first_ts) <= '2018-09-01'
                 AND p.second_ts IS NOT NULL
                 AND p.second_ts <= DATEADD(DAY, 90, p.first_ts) THEN 1 ELSE 0 END AS repeated_within_90d
    FROM person AS p
)
SELECT f.cohort_month,
       COUNT(*)                  AS cohort_people,
       SUM(f.repeated)           AS repeat_people,
       SUM(f.full_90d_window)    AS people_with_full_90d_window,
       SUM(f.repeated_within_90d) AS repeated_within_90d
FROM flags AS f
GROUP BY f.cohort_month
ORDER BY f.cohort_month;
GO

/* =====================================================================
   EXP_11  monthly_customers.csv   (filter dimension: purchase month)
   GRAIN   : one row per purchase month (20 rows, empty months kept)
   COLUMNS : purchase_month, delivered_orders, buying_people,
             merchandise_sales_brl
   buying_people = DISTINCT people with a delivered order in that month. It
   must NOT be summed across months (a person can buy in several months).
   ===================================================================== */
WITH months AS (
    SELECT CAST('2017-01-01' AS DATE) AS month_start
    UNION ALL
    SELECT DATEADD(MONTH, 1, month_start) FROM months WHERE month_start < '2018-08-01'
),
monthly AS (
    SELECT d.purchase_month,
           COUNT(*)                             AS delivered_orders,
           COUNT(DISTINCT d.customer_unique_id) AS buying_people,
           SUM(v.merchandise_value)             AS merchandise_sales_brl
    FROM dbo.vw_delivered_orders AS d
    JOIN dbo.vw_order_values     AS v ON v.order_id = d.order_id
    GROUP BY d.purchase_month
)
SELECT m.month_start AS purchase_month,
       COALESCE(mo.delivered_orders, 0)       AS delivered_orders,
       COALESCE(mo.buying_people, 0)          AS buying_people,
       COALESCE(mo.merchandise_sales_brl, 0)  AS merchandise_sales_brl
FROM months AS m
LEFT JOIN monthly AS mo ON mo.purchase_month = m.month_start
ORDER BY m.month_start
OPTION (MAXRECURSION 100);
GO

/* =====================================================================
   EXP_12  o2_category_repeat.csv  (question O2)
   GRAIN   : one row per pair type (All pairs / same timestamp / later) = 3 rows
   COLUMNS : pair_type, pairs_total, pairs_with_known_categories,
             pairs_repeating_a_category, pairs_only_new_categories
   ===================================================================== */
WITH order_seq AS (
    SELECT d.customer_unique_id, d.order_id, d.purchase_ts,
           ROW_NUMBER() OVER (PARTITION BY d.customer_unique_id
                              ORDER BY d.purchase_ts, d.order_id) AS order_seq
    FROM dbo.vw_delivered_orders AS d
),
pairs AS (
    SELECT a.order_id AS first_order_id, b.order_id AS second_order_id,
           CASE WHEN a.purchase_ts = b.purchase_ts THEN 1 ELSE 0 END AS same_timestamp
    FROM order_seq AS a
    JOIN order_seq AS b
      ON b.customer_unique_id = a.customer_unique_id AND a.order_seq = 1 AND b.order_seq = 2
),
flags AS (
    SELECT p.*,
           CASE WHEN EXISTS (SELECT 1 FROM dbo.vw_order_items AS i1
                             WHERE i1.order_id = p.first_order_id  AND i1.category_name <> 'unknown')
                 AND EXISTS (SELECT 1 FROM dbo.vw_order_items AS i2
                             WHERE i2.order_id = p.second_order_id AND i2.category_name <> 'unknown')
                THEN 1 ELSE 0 END AS both_orders_known,
           CASE WHEN EXISTS (SELECT 1 FROM dbo.vw_order_items AS i2
                             WHERE i2.order_id = p.second_order_id AND i2.category_name <> 'unknown'
                               AND EXISTS (SELECT 1 FROM dbo.vw_order_items AS i1
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
         - SUM(CASE WHEN f.both_orders_known = 1 THEN f.repeats_a_category ELSE 0 END) AS pairs_only_new_categories
FROM flags AS f
GROUP BY ROLLUP (f.same_timestamp)
ORDER BY GROUPING(f.same_timestamp) DESC, f.same_timestamp DESC;
GO
