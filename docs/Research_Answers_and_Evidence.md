# Research Answers and Evidence — Olist Customer Behavior (Track C)

All 12 questions with the answer, the query that produces it, the result table, the CSV export used by Excel, an explanation and the limitations.
Everything is reproducible: run `sql/01_schema.sql` → `02_validation.sql` → `03_analysis.sql` → `04_dashboard_exports.sql` (see README) and compare with the **Check value** of each question.

**Common rules:** window = purchases `2017-01-01` to `2018-08-31`; delivered orders only unless stated; money = merchandise sales in BRL (price, no freight); person = `customer_unique_id`; every rate shows numerator and denominator.

> **Source of values:** the 12 exported CSV files (`results/`) from SQL Server. Where a value differs from the `Expected` comment in `03_analysis.sql` (only C1 groups A and B, by 16 people), the exported value is used.

## Evidence index

| ID | Question | Query (script, line) | Export (`results/`) | Check value |
|---|---|---|---|---|
| G1 | Orders and status | `03_analysis.sql` G1.1 l.40, G1.2 l.49 | `kpi_overview.csv` (EXP_01) | 99,092 orders; 96,211 delivered |
| G2 | Monthly sales | `03_analysis.sql` G2 l.61 | – (chart from `monthly_customers.csv` EXP_11 and G2 result) | 20 rows; running total 13,181,027.13 |
| G3 | Missing review / payment | `03_analysis.sql` G3.1 l.130, G3.2 l.160, G3.3 l.169 | – | 643 without review; 0 without payment |
| C1 | Spend groups | `03_analysis.sql` C1.0 l.239, C1.1 l.246, C1.2 l.278 | `c1_value_groups.csv` (EXP_02) | P50 89.70; top 1% = 935 people |
| C2 | Repeat purchase and gaps | `03_analysis.sql` C2.1 l.320, C2.2 l.335, C2.3 l.361, C2.4 l.396 | `c2_orders_per_person.csv` (EXP_03), `c2_gap_bands.csv` (EXP_04) | 2,789 repeat of 93,104 |
| C3 | Above state average | `03_analysis.sql` C3.0 l.470, C3.1 l.474, C3.2 l.486 | `c3_state_summary.csv` (EXP_05) | 27 states; 27,061 above (29.07%) |
| C4 | Popular-category buyers | `03_analysis.sql` C4.0 l.523, C4.1 l.532 | `c4_segments.csv` (EXP_06) | 24,703 vs 68,401 people |
| C5 | Bought X not Y | `03_analysis.sql` C5.0 l.589, C5.1 l.598 | `c5_segments.csv` (EXP_07) | 8,975 (X not Y); 28 (both) |
| C6 | First vs second order | `03_analysis.sql` C6.1 l.673, C6.2 l.690, C6.3 l.698 | `c6_first_two.csv` (EXP_08) | 2,789 pairs |
| C7 | Single vs repeat experience | `03_analysis.sql` C7 l.708 | `c7_experience.csv` (EXP_09) | 90,315 single orders; 5,896 repeat orders |
| O1 | Cohorts and time to repeat | `03_analysis.sql` O1 l.776 | `o1_cohorts.csv` (EXP_10) | 75,448 full 90-day window; 1,717 repeated |
| O2 | Category repeat in 2nd order | `03_analysis.sql` O2 l.846 | `o2_category_repeat.csv` (EXP_12) | 2,789 pairs; 2,724 known |

---

## G1 — How many orders are there and what is their status?

**Answer.** 99,092 orders were purchased in the window; 96,211 (97.09%) were delivered. 96,211 delivered orders belong to 93,104 people and give 13,181,027.13 BRL merchandise sales (AOV 137.00 BRL).

| Status | Orders |
|---|---|
| delivered | 96,211 |
| shipped | 1,097 |
| unavailable | 602 |
| canceled | 580 |
| processing | 299 |
| invoiced | 296 |
| created | 5 |
| approved | 2 |

**Method.** Counts by `order_status` over `vw_orders_in_scope`; the percentage denominator is all 99,092 orders in the window.
**Limitation.** Status is the last known status in the snapshot; orders shown as "shipped" may have been delivered later.

## G2 — How do sales change from month to month?

**Answer.** Sales rise strongly during 2017 and peak in November 2017 (987,765.37 BRL, 7,289 orders). All 20 months are shown; Jan-2017 has no growth value because there is no previous month.

| Check | Value |
|---|---|
| Rows (months) | 20 |
| Sum of delivered orders | 96,211 |
| Jan-2017 | 111,798.36 BRL (750 orders) |
| Feb-2017 growth | +109.51% |
| Nov-2017 | 987,765.37 BRL (7,289 orders) |
| Final running total | 13,181,027.13 BRL |

**Method.** CTEs fill all months; `LAG()` gives the previous month for growth; `SUM() OVER (ORDER BY month ROWS UNBOUNDED PRECEDING)` gives the running total. Growth is NULL when the previous value is missing or 0.
**Limitation.** Early months start from a very small base, so percentage growth is large and should be read with the absolute values.

## G3 — Which delivered orders lack a review or a payment?

**Answer.** Payment data is complete (0 delivered orders without a payment record). 643 delivered orders (0.67%) have no valid review (score 1–5); no order misses both.

| Measure | Orders |
|---|---|
| Delivered | 96,211 |
| With valid review | 95,568 |
| Without review | 643 |
| With payment | 96,211 |
| Without payment | 0 |
| Missing both | 0 |

**Method.** `EXISTS` / `NOT EXISTS` flags computed in a CTE (SQL Server does not allow `SUM(CASE WHEN EXISTS …)` directly). G3.3 is expected to return 0 rows: an empty sample is a valid result.
**Limitation.** "No review" means no valid score; the customer may have been asked and not answered.

## C1 — How much do different customers spend?

**Answer.** Spending is concentrated. The top 10% of people (groups C and D) produce 41.12% of sales; the bottom half produces 16.67%. Mean spend is above the median (P50 = 89.70 BRL).

Cut-points: P50 = 89.70 | P90 = 279.99 | P99 = 1,004.99 BRL.

| Group | People | % people | Orders | Sales (BRL) | % sales | Avg spend |
|---|---|---|---|---|---|---|
| A. Lower (below P50) | 46,519 | 49.96 | 46,997 | 2,196,978.46 | 16.67 | 47.23 |
| B. Middle (P50–P90) | 37,267 | 40.03 | 38,889 | 5,564,596.01 | 42.22 | 149.32 |
| C. High (P90–P99) | 8,383 | 9.00 | 9,307 | 3,902,908.84 | 29.61 | 465.57 |
| D. Top 1% (≥ P99) | 935 | 1.00 | 1,018 | 1,516,543.82 | 11.51 | 1,621.97 |
| **Total** | **93,104** | | **96,211** | **13,181,027.13** | | |

Highest spender: 13,440.00 BRL.
**Note.** Group B starts at `>= P50`, so the 16 people who spent exactly 89.70 (= P50) belong to B. (The `Expected` comment in `03_analysis.sql` had them in A: 46,535 / 37,251.)
**Method.** `PERCENTILE_CONT` cut-points, then `CASE` groups. `NTILE` was rejected because many people spent exactly the same amount (1,574 people spent exactly 59.90) and NTILE would split them. Top-20 list uses `RANK()`.
**Limitation.** Spend is observed in 20 months, not lifetime value.

## C2 — How many customers purchase more than once?

**Answer.** 2,789 of 93,104 people (3.00%) placed 2 or more delivered orders. Counting only people with purchases on at least 2 different days: 2,005 (2.15%), because some second orders have the same timestamp (probably one basket split in two).

| Orders per person | People |
|---|---|
| 1 | 90,315 |
| 2 | 2,562 |
| 3 | 180 |
| 4 | 28 |
| 5 | 9 |
| 6 | 5 |
| 7 | 3 |
| 9 | 1 |
| 15 | 1 |

Gaps between consecutive purchases (3,107 pairs): average 78.20 days | median 29.37 | min 0.00 | max 582.86 | same-timestamp pairs 267 | pairs under 1 day 919 | average excluding same-timestamp pairs 85.55 (2,840 pairs).

| Gap band | Pairs |
|---|---|
| Same timestamp | 267 |
| >0 and <1 day | 652 |
| 1–29 days | 641 |
| 30–89 days | 584 |
| 90–179 days | 457 |
| 180+ days | 506 |

**Method.** `ROW_NUMBER()` per person (tie-break by `order_id`; 265 people have two orders with the identical timestamp), `LAG()` for the previous purchase; gap in seconds / 86400.
**Limitation.** Observed repetition only: not retention, not churn. A "single" customer may buy again after August 2018.

## C3 — Which customers spend more than their state average?

**Answer.** 27,061 people (29.07%) spend more than the average of their own state; 0 spend exactly the average. State averages differ: RJ (147.46) and MG (141.20) are above SP (129.48).

| State | People | Avg spend (BRL) | Above state avg | % above |
|---|---|---|---|---|
| SP | 39,059 | 129.48 | 11,599 | 29.70 |
| RJ | 11,877 | 147.46 | 3,488 | 29.37 |
| MG | 10,963 | 141.20 | 3,171 | 28.92 |
| RR (smallest) | 39 | 179.94 | 13 | 33.33 |
| AP | 66 | 202.65 | 16 | 24.24 |

Top person: 13,440.00 BRL (RJ), +13,292.54 above the state average 147.46; next 7,388.00 (RJ) and 7,160.00 (ES).
**Method.** Correlated subquery against a state average (including the person compared); people-level result stored in `#temp` with an index. 36 people bought from more than one state and are counted once, in the state of their latest order.
**Limitation.** Small states (RR, AP) have very few people, so their percentages are unstable.

## C4 — Do buyers of the most popular categories behave differently?

**Answer.** Buyers of the 3 most popular categories (by distinct buyers) repeat more often (5.00% vs 2.27%) but spend slightly less per person (134.29 vs 144.20 BRL).

Top categories by buyers: bed_bath_table 9,003 | health_beauty 8,462 | sports_leisure 7,324 (then computers_accessories 6,393, furniture_decor 6,130).

| Segment | People | Sales (BRL) | Per person | Repeat people | Repeat % | Orders/person |
|---|---|---|---|---|---|---|
| Top-3 category buyers | 24,703 | 3,317,486.20 | 134.29 | 1,235 | 5.00 | 1.06 |
| All other buyers | 68,401 | 9,863,540.93 | 144.20 | 1,554 | 2.27 | 1.02 |

**Method.** `IN (SELECT TOP (3) …)` multi-row subquery; segments do not overlap and sum to 93,104 people. Spend is the person's total spend in all categories.
**Limitation.** Shows exposure to popular categories, not preference; popular categories are popular partly because they are large.

## C5 — Who bought category X but not category Y?

X = `bed_bath_table` (9,267 orders / 9,003 people), Y = `health_beauty` (8,610 orders / 8,462 people).

**Answer.** 8,975 people bought X but not Y (repeat 6.24%). Only 28 people bought both.

| Segment | People | Sales (BRL) | Per person | Orders/person | Repeat % |
|---|---|---|---|---|---|
| X not Y | 8,975 | 1,081,330.36 | 120.48 | 1.072 | 6.24 |
| X and Y | 28 | 6,637.87 | 237.07 | 1.857 | 64.29 |

**Method.** `EXISTS` for X and `NOT EXISTS` for Y per person.
**Limitation.** "Not Y" means not within the window; the person may have bought Y elsewhere or later. The "both" group (28 people) is too small for firm conclusions.

## C6 — How do the first two purchases compare?

**Answer.** The second order is about as large as the first (122.85 vs 123.28 BRL, difference −0.44). The second is larger for 45.61% of people. The typical wait is about a month (median 28.98 days).

| Measure | All pairs (C6.1) | Without same-timestamp pairs (C6.2) |
|---|---|---|
| Pairs | 2,789 | 2,536 |
| Avg first order | 123.28 | – |
| Avg second order | 122.85 | – |
| Avg gap (days) | 80.22 | 88.23 |
| Median gap (days) | 28.98 | – |
| Second larger | 1,272 (45.61%) | 46.18% |
| Equal / smaller | 317 / 1,200 | – |

Same-timestamp pairs 253; pairs under 1 day 850.
**Method.** Self-join of `order_seq = 1` to `order_seq = 2` of the same person (CTE with `ROW_NUMBER`).
**Limitation.** The "second order" is only the second *observed* order in the window.

## C7 — Do single-order and repeat customers have different experiences?

**Answer.** Differences are small. Repeat customers have slightly fewer late deliveries and low ratings, and a slightly higher average score. These are associations, not causes.

| Group (all orders) | Orders | Avg delivery days | Late | Reviewed | Avg score | Low rating (1–2) |
|---|---|---|---|---|---|---|
| Single-order customers | 90,315 | 12.55 | 6,192 (6.86%) | 89,724 (99.35%) | 4.152 | 11,536 (12.86%) |
| Repeat customers | 5,896 | 12.30 | 339 (5.75%) | 5,844 (99.12%) | 4.216 | 693 (11.86%) |

First delivered order only (same experience before any repeat purchase): repeat customers 2,789 orders | 12.40 days | late 160 (5.74%) | reviewed 2,768 (99.25%) | score 4.199 | low 334 (12.07%). Single-order customers are unchanged (their only order is their first).
**Method.** `LEFT JOIN` to the one-review-per-order view so orders without review stay in the denominators. Late rate = late / orders with valid dates; low-rating rate = low / valid reviews.
**Limitation.** Short window; "single" customers may still buy again; many other factors (category, region) are not controlled.

## O1 — Does repeat share depend on when a person first bought?

**Answer.** The falling repeat share in recent cohorts is mostly a time effect. The share who repeated within a full 90-day window is much flatter.

Totals: 20 cohorts | 93,104 people | 2,789 repeat | 75,448 with a full 90-day window | 1,717 repeated within 90 days (2.28%).

| First-order month | People | Repeat (any time) | With full 90-day window | Repeat within 90 days |
|---|---|---|---|---|
| 2017-01 | 718 | 52 (7.24%) | 718 | 26 (3.62%) |
| 2017-05 | 3,451 | 182 (5.27%) | 3,451 | 98 (2.84%) |
| 2018-05 | 6,508 | 109 (1.67%) | 6,508 | 105 (1.61%) |
| 2018-06 | 5,879 | 70 (1.19%) | 316 (partial) | 6 (1.90%) |
| 2018-07 | 5,949 | 88 (1.48%) | none | NULL |
| 2018-08 | 6,144 | 34 (0.55%) | none | NULL |

**Method.** Cohort = month of first order; full window = first order + 90 days ≤ 2018-09-01 (`DATEADD`, `DATEFROMPARTS`). Only the 90-day share is comparable across cohorts.
**Limitation.** Cohorts marked partial or none should not be compared. Descriptive only.

## O2 — Is the second order in a category the person already bought?

**Answer.** About half of second orders (47.50% of pairs with known categories) include a category already bought in the first order; the rest open only new categories.

| Group | Pairs | Known category | Repeating a category | Only new | % repeating |
|---|---|---|---|---|---|
| All pairs | 2,789 | 2,724 | 1,294 | 1,430 | 47.50 |
| Same timestamp | 253 | 246 | 165 | 81 | 67.07 |
| Later | 2,536 | 2,478 | 1,129 | 1,349 | 45.56 |

65 pairs without a known category in one of the two orders are counted separately. Category `unknown` is not used for matching.
**Method.** Nested `EXISTS` in CTEs; `GROUP BY ROLLUP` with `GROUPING()` gives the subtotal row. Same-timestamp pairs (probably one basket split in two) are shown separately.
**Limitation.** Descriptive; it does not show why people choose a category.

---

## How to check any result quickly

1. Run the query at the line shown in the evidence index (each block is self-contained after steps 01 and 02).
2. Compare with the **Check value** and with the table above.
3. For dashboard figures, open the matching CSV in `results/`; Excel recomputes rates from the supporting sums and counts, and the KPI reconciliation sheet compares them with the SQL totals.
