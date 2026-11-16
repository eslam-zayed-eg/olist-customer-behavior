# SQL Coverage Map — Olist BI (Track C)

Links every SQL topic used in the project to the question IDs and the script location.
Line numbers refer to the current version of each script; update them if you edit the files.

> **Check before submitting:** the brief (not fully visible to me) has its own list of *required* SQL topics.
> Compare the "SQL topic" column below with that list and add a row for any topic that is missing.

| SQL topic | Question IDs | Script and location | Analytical purpose |
|---|---|---|---|
| **Staging + BULK INSERT import** | – | `01_schema.sql` §2–3 | Load the 8 CSVs as raw text so row counts always match the source. |
| **Type conversion (`TRY_CONVERT`, `NULLIF`)** | – | `01_schema.sql` §5 | Typed tables; blank → NULL, bad values → NULL and counted. |
| **Aggregation, `COUNT(DISTINCT)`** | G1, C1–C7, O1 | `03_analysis.sql` G1.1 (l.40), C2.1 (l.320) | Orders, people, sales, key-uniqueness checks. |
| **Scalar subquery** | G1 | `03_analysis.sql` G1.1 (l.40) | Percentage denominator = all orders in the window. |
| **CTE (single and chained)** | G2, C1, C2, C4, C6, O1, O2 | `03_analysis.sql` G2 (l.61), C1.1 (l.246), O1 (l.776) | Build the analysis step by step with one clear grain per step. |
| **Window: `LAG`** | G2, C2 | `03_analysis.sql` G2 (l.66), C2.3 (l.343) | Previous month, gap between consecutive purchases. |
| **Window: running total (`SUM … OVER`)** | G2 | `03_analysis.sql` G2 (l.61) | Cumulative monthly sales. |
| **Window: `SUM() OVER ()` for shares** | C1, C4 | `03_analysis.sql` C1.1 (l.246) | Share of customers / sales per group. |
| **`ROW_NUMBER()`** | C2, C6, O1, O2, `vw_order_review` | `03_analysis.sql` C2 (l.343), C6 (l.628), O1; `02_validation.sql` 5-B | Order sequence per person; one review per order. |
| **`RANK()` ranking function** | C1 | `03_analysis.sql` C1.2 (l.278) | Top-20 spenders; equal spenders share a rank. |
| **`PERCENTILE_CONT`** | C1 | `03_analysis.sql` C1.0–C1.1 (l.239–246) | Value groups by P50 / P90 / P99 (NTILE rejected: it splits equal spenders). |
| **`EXISTS`** | G3, C5, O2 | `03_analysis.sql` G3.1 (l.130), C5 (l.566), O2 (l.846) | Test whether a related record exists (review, payment, category bought). |
| **`NOT EXISTS`** | G3, C5 | `03_analysis.sql` G3.2–G3.3 (l.160–169), C5.1 (l.598) | Orders without review/payment; bought X but not Y. |
| **Nested / correlated `EXISTS`** | O2 | `03_analysis.sql` O2 (l.846) | Second order contains a category already in the first order. |
| **Correlated subquery** | C3 | `03_analysis.sql` C3 (l.406) | Compare each person with their state average. |
| **Multi-row subquery (`IN (SELECT …)`)** | C4 | `03_analysis.sql` C4 (l.500) | People who bought from the top-3 categories. |
| **Derived table** | C2, G3, vw_order_values | `03_analysis.sql` C2.1; `02_validation.sql` 5-B | One-row-per-key subquery that prevents join fan-out. |
| **`INNER JOIN`** | all views | `02_validation.sql` 5-B | orders → customers, items → products (0 orphans proved first). |
| **`LEFT JOIN`** | G3, C7, `vw_order_items` | `02_validation.sql` 5-B; `03_analysis.sql` C7 (l.708) | Keep rows without a match (untranslated category, no review). |
| **Self-join** | C6 | `03_analysis.sql` C6 (l.628) | First order (seq 1) joined to second order (seq 2) of the same person. |
| **`UNION ALL`** | G1/validation | `02_validation.sql` Parts 1–5 | Stack check results into one table. |
| **`CROSS APPLY`** | delivery metrics | `02_validation.sql` 5-B (`vw_delivered_orders`) | Compute the valid-date flag once and reuse it. |
| **`CASE` / conditional aggregation** | C1, C2, C7, O1 | `03_analysis.sql` C1.1, C7, O1 (l.776) | Groups, flags, repeat-within-90-days. |
| **`GROUP BY ROLLUP` + `GROUPING()`** | O2 | `03_analysis.sql` l.914; `04_dashboard_exports.sql` l.388 | Subtotal row "all pairs" beside the same-timestamp split. |
| **Date functions** (`DATEDIFF`, `DATEADD`, `DATEFROMPARTS`) | G2, C2, O1, delivery metrics | `02_validation.sql` 5-B; `03_analysis.sql` O1 | Months, delivery days, 90-day window, late rule. |
| **Temporary tables (`#…`)** | C3, C6, C7 | `03_analysis.sql` l.450, 666, 751 | Store the people-level result once, reuse in several queries. |
| **Views** | all | `02_validation.sql` 5-B; `03_analysis.sql` l.195 | One place for window, delivered filter, one-review-per-order rule. |
| **Constraints (PK / FK `WITH CHECK`)** | – | `02_validation.sql` 5-A (l.644) | Added only after uniqueness and orphan tests passed. |
| **Validation queries** | – | `02_validation.sql` Parts 1–4 | CR characters, failed conversions, NULLs, duplicates, orphans, ranges. |
| **NULL-safe division (`NULLIF`, `COALESCE`)** | all rates | `03_analysis.sql`, `04_dashboard_exports.sql` | Rates never divide by zero; numerator and denominator are shown. |
| **Dashboard export queries** | G1, C1, C2 … | `04_dashboard_exports.sql` EXP_01 … | Tables with supporting sums/counts for Excel to recompute rates. |

## Question index (where each answer is)

| ID | Question | Location |
|---|---|---|
| G1 | How many orders, and what is their status? | `03_analysis.sql` l.26 |
| G2 | How do sales change month to month? | l.61 |
| G3 | Which delivered orders lack a review or payment? | l.113 |
| C1 | How much do different customers spend? | l.209 |
| C2 | How many customers purchase more than once? | l.290 |
| C3 | Which customers spend more than their state average? | l.406 |
| C4 | Who purchases from popular categories? | l.500 |
| C5 | Who bought category X but not Y? | l.566 |
| C6 | How do the first two purchases compare? | l.628 |
| C7 | Do single-order and repeat customers have different experiences? | l.708 |
| O1 | Does repeat share depend on when a person first bought? | l.776 |
| O2 | Is the second order in a category already bought? | l.846 |

## Not used (state this honestly if the brief lists it)

- `HAVING`, `INTERSECT`, `EXCEPT`, `PIVOT`, `STRING_AGG`: not used in the scripts.
- `NTILE`: mentioned only as a rejected option in C1 (percentile cut-points are used instead).
