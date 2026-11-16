/* =====================================================================
   FILE      : sql/02_validation.sql
   PROJECT   : BI-Olist-Analytics
   PURPOSE   : Profile and validate the imported data BEFORE analysis.
               Nothing in this file changes the data until the
               constraint / view sections (added in later parts).
   RUN ORDER : after 01_schema.sql
   STATUS    : GENERATED CODE - the expected values written in the
               comments were measured on the original CSV files with
               Python/pandas; the SQL itself is NOT yet tested.

   PARTS
     Part 1 : import integrity (hidden characters, failed conversions,
              NULL profile)
     Part 2 : candidate keys and duplicates                    <- added
     Part 3 : unmatched relationships (orphans) and coverage   <- added
     Part 4 : value ranges, dates, impossible values           <- added
     Part 5 : 5-A constraints (PK / FK)                        <- added
              5-B analysis-ready views + view checks              <- added
   ===================================================================== */
USE OlistBI;
GO
SET NOCOUNT ON;
GO

/* =====================================================================
   PART 1-A : Hidden carriage-return (CR) characters
   Question : did a wrong row terminator leave a CR at the end of the
              LAST column of any file?
   Grain    : one row per checked column
   Expected : 0 rows with CR everywhere
   ===================================================================== */
SELECT 'customers.customer_state' AS checked_column, COUNT(*) AS rows_with_cr
FROM stg.customers WHERE customer_state LIKE '%' + CHAR(13) + '%'
UNION ALL
SELECT 'orders.order_estimated_delivery_date', COUNT(*)
FROM stg.orders WHERE order_estimated_delivery_date LIKE '%' + CHAR(13) + '%'
UNION ALL
SELECT 'order_items.freight_value', COUNT(*)
FROM stg.order_items WHERE freight_value LIKE '%' + CHAR(13) + '%'
UNION ALL
SELECT 'products.product_width_cm', COUNT(*)
FROM stg.products WHERE product_width_cm LIKE '%' + CHAR(13) + '%'
UNION ALL
SELECT 'sellers.seller_state', COUNT(*)
FROM stg.sellers WHERE seller_state LIKE '%' + CHAR(13) + '%'
UNION ALL
SELECT 'order_payments.payment_value', COUNT(*)
FROM stg.order_payments WHERE payment_value LIKE '%' + CHAR(13) + '%'
UNION ALL
SELECT 'order_reviews.review_answer_timestamp', COUNT(*)
FROM stg.order_reviews WHERE review_answer_timestamp LIKE '%' + CHAR(13) + '%'
UNION ALL
SELECT 'category_translation.product_category_name_english', COUNT(*)
FROM stg.category_translation WHERE product_category_name_english LIKE '%' + CHAR(13) + '%';
GO

/* =====================================================================
   PART 1-B : Failed type conversions
   Question : did TRY_CONVERT turn a real value into NULL?
   Logic    : for every converted column compare
                source_nonblank = rows whose staging text is not blank
                typed_nonnull   = rows whose typed value is not NULL
              Both must be equal. (Blank text is meant to become NULL,
              so it is not counted as a failure.)
   Grain    : one row per converted column
   Expected : failed_conversions = 0, check_result = PASS
   ===================================================================== */
WITH conv AS (
    -- orders (5 date columns)
    SELECT 'orders.order_purchase_timestamp' AS table_column,
           (SELECT COUNT(*) FROM stg.orders WHERE NULLIF(LTRIM(RTRIM(order_purchase_timestamp)), '') IS NOT NULL) AS source_nonblank,
           (SELECT COUNT(order_purchase_timestamp) FROM dbo.orders) AS typed_nonnull
    UNION ALL SELECT 'orders.order_approved_at',
           (SELECT COUNT(*) FROM stg.orders WHERE NULLIF(LTRIM(RTRIM(order_approved_at)), '') IS NOT NULL),
           (SELECT COUNT(order_approved_at) FROM dbo.orders)
    UNION ALL SELECT 'orders.order_delivered_carrier_date',
           (SELECT COUNT(*) FROM stg.orders WHERE NULLIF(LTRIM(RTRIM(order_delivered_carrier_date)), '') IS NOT NULL),
           (SELECT COUNT(order_delivered_carrier_date) FROM dbo.orders)
    UNION ALL SELECT 'orders.order_delivered_customer_date',
           (SELECT COUNT(*) FROM stg.orders WHERE NULLIF(LTRIM(RTRIM(order_delivered_customer_date)), '') IS NOT NULL),
           (SELECT COUNT(order_delivered_customer_date) FROM dbo.orders)
    UNION ALL SELECT 'orders.order_estimated_delivery_date',
           (SELECT COUNT(*) FROM stg.orders WHERE NULLIF(LTRIM(RTRIM(order_estimated_delivery_date)), '') IS NOT NULL),
           (SELECT COUNT(order_estimated_delivery_date) FROM dbo.orders)
    -- order_items
    UNION ALL SELECT 'order_items.order_item_id',
           (SELECT COUNT(*) FROM stg.order_items WHERE NULLIF(LTRIM(RTRIM(order_item_id)), '') IS NOT NULL),
           (SELECT COUNT(order_item_id) FROM dbo.order_items)
    UNION ALL SELECT 'order_items.shipping_limit_date',
           (SELECT COUNT(*) FROM stg.order_items WHERE NULLIF(LTRIM(RTRIM(shipping_limit_date)), '') IS NOT NULL),
           (SELECT COUNT(shipping_limit_date) FROM dbo.order_items)
    UNION ALL SELECT 'order_items.price',
           (SELECT COUNT(*) FROM stg.order_items WHERE NULLIF(LTRIM(RTRIM(price)), '') IS NOT NULL),
           (SELECT COUNT(price) FROM dbo.order_items)
    UNION ALL SELECT 'order_items.freight_value',
           (SELECT COUNT(*) FROM stg.order_items WHERE NULLIF(LTRIM(RTRIM(freight_value)), '') IS NOT NULL),
           (SELECT COUNT(freight_value) FROM dbo.order_items)
    -- products (7 numeric columns)
    UNION ALL SELECT 'products.product_name_lenght',
           (SELECT COUNT(*) FROM stg.products WHERE NULLIF(LTRIM(RTRIM(product_name_lenght)), '') IS NOT NULL),
           (SELECT COUNT(product_name_lenght) FROM dbo.products)
    UNION ALL SELECT 'products.product_description_lenght',
           (SELECT COUNT(*) FROM stg.products WHERE NULLIF(LTRIM(RTRIM(product_description_lenght)), '') IS NOT NULL),
           (SELECT COUNT(product_description_lenght) FROM dbo.products)
    UNION ALL SELECT 'products.product_photos_qty',
           (SELECT COUNT(*) FROM stg.products WHERE NULLIF(LTRIM(RTRIM(product_photos_qty)), '') IS NOT NULL),
           (SELECT COUNT(product_photos_qty) FROM dbo.products)
    UNION ALL SELECT 'products.product_weight_g',
           (SELECT COUNT(*) FROM stg.products WHERE NULLIF(LTRIM(RTRIM(product_weight_g)), '') IS NOT NULL),
           (SELECT COUNT(product_weight_g) FROM dbo.products)
    UNION ALL SELECT 'products.product_length_cm',
           (SELECT COUNT(*) FROM stg.products WHERE NULLIF(LTRIM(RTRIM(product_length_cm)), '') IS NOT NULL),
           (SELECT COUNT(product_length_cm) FROM dbo.products)
    UNION ALL SELECT 'products.product_height_cm',
           (SELECT COUNT(*) FROM stg.products WHERE NULLIF(LTRIM(RTRIM(product_height_cm)), '') IS NOT NULL),
           (SELECT COUNT(product_height_cm) FROM dbo.products)
    UNION ALL SELECT 'products.product_width_cm',
           (SELECT COUNT(*) FROM stg.products WHERE NULLIF(LTRIM(RTRIM(product_width_cm)), '') IS NOT NULL),
           (SELECT COUNT(product_width_cm) FROM dbo.products)
    -- order_payments
    UNION ALL SELECT 'order_payments.payment_sequential',
           (SELECT COUNT(*) FROM stg.order_payments WHERE NULLIF(LTRIM(RTRIM(payment_sequential)), '') IS NOT NULL),
           (SELECT COUNT(payment_sequential) FROM dbo.order_payments)
    UNION ALL SELECT 'order_payments.payment_installments',
           (SELECT COUNT(*) FROM stg.order_payments WHERE NULLIF(LTRIM(RTRIM(payment_installments)), '') IS NOT NULL),
           (SELECT COUNT(payment_installments) FROM dbo.order_payments)
    UNION ALL SELECT 'order_payments.payment_value',
           (SELECT COUNT(*) FROM stg.order_payments WHERE NULLIF(LTRIM(RTRIM(payment_value)), '') IS NOT NULL),
           (SELECT COUNT(payment_value) FROM dbo.order_payments)
    -- order_reviews
    UNION ALL SELECT 'order_reviews.review_score',
           (SELECT COUNT(*) FROM stg.order_reviews WHERE NULLIF(LTRIM(RTRIM(review_score)), '') IS NOT NULL),
           (SELECT COUNT(review_score) FROM dbo.order_reviews)
    UNION ALL SELECT 'order_reviews.review_creation_date',
           (SELECT COUNT(*) FROM stg.order_reviews WHERE NULLIF(LTRIM(RTRIM(review_creation_date)), '') IS NOT NULL),
           (SELECT COUNT(review_creation_date) FROM dbo.order_reviews)
    UNION ALL SELECT 'order_reviews.review_answer_timestamp',
           (SELECT COUNT(*) FROM stg.order_reviews WHERE NULLIF(LTRIM(RTRIM(review_answer_timestamp)), '') IS NOT NULL),
           (SELECT COUNT(review_answer_timestamp) FROM dbo.order_reviews)
)
SELECT table_column,
       source_nonblank,
       typed_nonnull,
       source_nonblank - typed_nonnull AS failed_conversions,
       CASE WHEN source_nonblank = typed_nonnull THEN 'PASS' ELSE 'FAIL' END AS check_result
FROM conv
ORDER BY table_column;
GO

/* =====================================================================
   PART 1-C : NULL profile of the typed tables
   Question : how many NULLs does each important column have, and does
              that match the original CSV files?
   Grain    : one row per column
   Expected : "expected_nulls" were counted on the original CSV files with
              pandas (blank = missing). Key columns must have 0.
   Treatment (decided here, applied later):
     * NULL delivery / approval dates are NOT errors: the order simply has
       not reached that step (canceled, shipped, unavailable ...). Rows are
       kept; each metric excludes NULL pairs and reports how many it excluded.
     * NULL product category / dimensions: kept. Category NULL is shown as
       'unknown' in analysis (LEFT JOIN, never INNER JOIN).
     * NULL review comment title / message: normal (most reviews have no text).
       Expected = blank in the CSV (87,656 title / 58,247 message) PLUS
       comments made only of spaces, which are deliberately treated as blank
       (2 titles / 9 messages) = 87,658 and 58,256. Emoji-only comments
       (8 titles / 18 messages) must be KEPT, not turned into NULL.
   ===================================================================== */
WITH nulls AS (
    SELECT 'orders.order_id' AS table_column, 0 AS expected_nulls,
           SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS actual_nulls FROM dbo.orders
    UNION ALL SELECT 'orders.customer_id', 0, SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) FROM dbo.orders
    UNION ALL SELECT 'orders.order_purchase_timestamp', 0, SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) FROM dbo.orders
    UNION ALL SELECT 'orders.order_approved_at', 160, SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END) FROM dbo.orders
    UNION ALL SELECT 'orders.order_delivered_carrier_date', 1783, SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END) FROM dbo.orders
    UNION ALL SELECT 'orders.order_delivered_customer_date', 2965, SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) FROM dbo.orders
    UNION ALL SELECT 'orders.order_estimated_delivery_date', 0, SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) FROM dbo.orders
    UNION ALL SELECT 'customers.customer_unique_id', 0, SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END) FROM dbo.customers
    UNION ALL SELECT 'customers.customer_state', 0, SUM(CASE WHEN customer_state IS NULL THEN 1 ELSE 0 END) FROM dbo.customers
    UNION ALL SELECT 'order_items.price', 0, SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END) FROM dbo.order_items
    UNION ALL SELECT 'order_items.freight_value', 0, SUM(CASE WHEN freight_value IS NULL THEN 1 ELSE 0 END) FROM dbo.order_items
    UNION ALL SELECT 'products.product_category_name', 610, SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END) FROM dbo.products
    UNION ALL SELECT 'products.product_name_lenght', 610, SUM(CASE WHEN product_name_lenght IS NULL THEN 1 ELSE 0 END) FROM dbo.products
    UNION ALL SELECT 'products.product_description_lenght', 610, SUM(CASE WHEN product_description_lenght IS NULL THEN 1 ELSE 0 END) FROM dbo.products
    UNION ALL SELECT 'products.product_photos_qty', 610, SUM(CASE WHEN product_photos_qty IS NULL THEN 1 ELSE 0 END) FROM dbo.products
    UNION ALL SELECT 'products.product_weight_g', 2, SUM(CASE WHEN product_weight_g IS NULL THEN 1 ELSE 0 END) FROM dbo.products
    UNION ALL SELECT 'products.product_length_cm', 2, SUM(CASE WHEN product_length_cm IS NULL THEN 1 ELSE 0 END) FROM dbo.products
    UNION ALL SELECT 'products.product_height_cm', 2, SUM(CASE WHEN product_height_cm IS NULL THEN 1 ELSE 0 END) FROM dbo.products
    UNION ALL SELECT 'products.product_width_cm', 2, SUM(CASE WHEN product_width_cm IS NULL THEN 1 ELSE 0 END) FROM dbo.products
    UNION ALL SELECT 'sellers.seller_state', 0, SUM(CASE WHEN seller_state IS NULL THEN 1 ELSE 0 END) FROM dbo.sellers
    UNION ALL SELECT 'order_payments.payment_value', 0, SUM(CASE WHEN payment_value IS NULL THEN 1 ELSE 0 END) FROM dbo.order_payments
    UNION ALL SELECT 'order_reviews.review_score', 0, SUM(CASE WHEN review_score IS NULL THEN 1 ELSE 0 END) FROM dbo.order_reviews
    UNION ALL SELECT 'order_reviews.review_comment_title', 87658, SUM(CASE WHEN review_comment_title IS NULL THEN 1 ELSE 0 END) FROM dbo.order_reviews
    UNION ALL SELECT 'order_reviews.review_comment_message', 58256, SUM(CASE WHEN review_comment_message IS NULL THEN 1 ELSE 0 END) FROM dbo.order_reviews
)
SELECT table_column,
       expected_nulls,
       actual_nulls,
       CASE WHEN expected_nulls = actual_nulls THEN 'PASS' ELSE 'FAIL' END AS check_result
FROM nulls
ORDER BY table_column;
GO

/* =====================================================================
   PART 2-A : Candidate-key uniqueness
   Question : is each candidate key from the PDF really unique?
   Logic    : total rows vs distinct key values.
              For composite keys the DISTINCT is done in a derived table
              (grain: one row per key combination).
   Grain    : one row per table / key
   Expected : duplicate_rows = 0 everywhere EXCEPT order_reviews.review_id,
              which has 814 duplicates in the source (measured with pandas).
              That one is NOT a key - see Part 2-B for how it is treated.
   ===================================================================== */
WITH keys AS (
    SELECT 'customers' AS table_name, 'customer_id' AS candidate_key,
           COUNT(*) AS total_rows, COUNT(DISTINCT customer_id) AS distinct_keys,
           0 AS expected_duplicates
    FROM dbo.customers
    UNION ALL SELECT 'orders', 'order_id', COUNT(*), COUNT(DISTINCT order_id), 0
    FROM dbo.orders
    UNION ALL SELECT 'products', 'product_id', COUNT(*), COUNT(DISTINCT product_id), 0
    FROM dbo.products
    UNION ALL SELECT 'sellers', 'seller_id', COUNT(*), COUNT(DISTINCT seller_id), 0
    FROM dbo.sellers
    UNION ALL SELECT 'category_translation', 'product_category_name',
           COUNT(*), COUNT(DISTINCT product_category_name), 0
    FROM dbo.category_translation
    UNION ALL SELECT 'order_items', '(order_id, order_item_id)',
           (SELECT COUNT(*) FROM dbo.order_items),
           (SELECT COUNT(*) FROM (SELECT DISTINCT order_id, order_item_id FROM dbo.order_items) AS k),
           0
    UNION ALL SELECT 'order_payments', '(order_id, payment_sequential)',
           (SELECT COUNT(*) FROM dbo.order_payments),
           (SELECT COUNT(*) FROM (SELECT DISTINCT order_id, payment_sequential FROM dbo.order_payments) AS k),
           0
    UNION ALL SELECT 'order_reviews', 'review_id  (NOT a key)',
           COUNT(*), COUNT(DISTINCT review_id), 814
    FROM dbo.order_reviews
    UNION ALL SELECT 'order_reviews', '(review_id, order_id)',
           (SELECT COUNT(*) FROM dbo.order_reviews),
           (SELECT COUNT(*) FROM (SELECT DISTINCT review_id, order_id FROM dbo.order_reviews) AS k),
           0
    UNION ALL SELECT 'order_reviews', 'source_row_id  (our own key)',
           COUNT(*), COUNT(DISTINCT source_row_id), 0
    FROM dbo.order_reviews
)
SELECT table_name,
       candidate_key,
       total_rows,
       distinct_keys,
       total_rows - distinct_keys AS duplicate_rows,
       expected_duplicates,
       CASE WHEN total_rows - distinct_keys = expected_duplicates THEN 'PASS' ELSE 'FAIL' END AS check_result
FROM keys
ORDER BY table_name, candidate_key;
GO

/* =====================================================================
   PART 2-B : Reviews - why review_id cannot be the key, and how many
              orders have more than one review
   Grain    : one summary row (derived table = one row per order, and one
              row per review_id)
   Expected (measured with pandas on the CSV):
       total_review_rows           99,224
       distinct_review_ids         98,410
       orders_with_a_review        98,673
       orders_with_2plus_reviews      547    (543 with 2, 4 with 3)
       review_ids_on_2plus_orders     789
   Treatment (the PDF's rule): source review rows are KEPT unchanged.
       One analysis review per order is chosen later (Part 5 view) among
       valid scores: latest review_answer_timestamp, then review_creation_date,
       then review_id, then source_row_id; NULL timestamps count as oldest.
   ===================================================================== */
SELECT (SELECT COUNT(*) FROM dbo.order_reviews)                  AS total_review_rows,
       (SELECT COUNT(DISTINCT review_id) FROM dbo.order_reviews) AS distinct_review_ids,
       o.orders_with_a_review,
       o.orders_with_2plus_reviews,
       r.review_ids_on_2plus_orders
FROM (SELECT COUNT(*) AS orders_with_a_review,
             SUM(CASE WHEN review_rows > 1 THEN 1 ELSE 0 END) AS orders_with_2plus_reviews
      FROM (SELECT order_id, COUNT(*) AS review_rows      -- grain: one row per order
            FROM dbo.order_reviews
            GROUP BY order_id) AS per_order) AS o
CROSS JOIN
     (SELECT COUNT(*) AS review_ids_on_2plus_orders
      FROM (SELECT review_id                              -- grain: one row per review_id
            FROM dbo.order_reviews
            GROUP BY review_id
            HAVING COUNT(DISTINCT order_id) > 1) AS shared_ids) AS r;

-- Distribution: how many orders have 1, 2, 3 ... review rows?
-- Expected: 1 -> 98,126 | 2 -> 543 | 3 -> 4
SELECT review_rows AS reviews_per_order,
       COUNT(*)    AS orders
FROM (SELECT order_id, COUNT(*) AS review_rows            -- grain: one row per order
      FROM dbo.order_reviews
      GROUP BY order_id) AS per_order
GROUP BY review_rows
ORDER BY review_rows;
GO

/* =====================================================================
   PART 2-C : customer_id vs customer_unique_id
   Question : how different are "customer records" and "people"?
   Grain    : one summary row
   Expected : customer_id_rows 99,441 | distinct_people 96,096 |
              people_with_2plus_customer_ids 2,997 | max_ids_for_one_person 17
   Rule     : people = DISTINCT customer_unique_id (PDF, Section 8).
              orders join to customers on customer_id (never on unique id).
   ===================================================================== */
SELECT (SELECT COUNT(*) FROM dbo.customers)                       AS customer_id_rows,
       COUNT(*)                                                    AS distinct_people,
       SUM(CASE WHEN ids_per_person > 1 THEN 1 ELSE 0 END)         AS people_with_2plus_customer_ids,
       MAX(ids_per_person)                                         AS max_ids_for_one_person
FROM (SELECT customer_unique_id, COUNT(*) AS ids_per_person   -- grain: one row per person
      FROM dbo.customers
      GROUP BY customer_unique_id) AS per_person;
GO

/* =====================================================================
   PART 3-A : Orphans  (child rows whose parent does not exist)
   Question : does every foreign key point to an existing parent row?
   Logic    : NOT EXISTS against the parent table.
   Grain    : one row per relationship
   Expected : 0 orphans everywhere (measured on the CSVs with pandas)
   ===================================================================== */
WITH orphans AS (
    SELECT 'orders.customer_id -> customers' AS relationship, COUNT(*) AS orphan_rows
    FROM dbo.orders AS o
    WHERE NOT EXISTS (SELECT 1 FROM dbo.customers AS c WHERE c.customer_id = o.customer_id)
    UNION ALL
    SELECT 'order_items.order_id -> orders', COUNT(*)
    FROM dbo.order_items AS i
    WHERE NOT EXISTS (SELECT 1 FROM dbo.orders AS o WHERE o.order_id = i.order_id)
    UNION ALL
    SELECT 'order_items.product_id -> products', COUNT(*)
    FROM dbo.order_items AS i
    WHERE NOT EXISTS (SELECT 1 FROM dbo.products AS p WHERE p.product_id = i.product_id)
    UNION ALL
    SELECT 'order_items.seller_id -> sellers', COUNT(*)
    FROM dbo.order_items AS i
    WHERE NOT EXISTS (SELECT 1 FROM dbo.sellers AS s WHERE s.seller_id = i.seller_id)
    UNION ALL
    SELECT 'order_payments.order_id -> orders', COUNT(*)
    FROM dbo.order_payments AS pay
    WHERE NOT EXISTS (SELECT 1 FROM dbo.orders AS o WHERE o.order_id = pay.order_id)
    UNION ALL
    SELECT 'order_reviews.order_id -> orders', COUNT(*)
    FROM dbo.order_reviews AS r
    WHERE NOT EXISTS (SELECT 1 FROM dbo.orders AS o WHERE o.order_id = r.order_id)
)
SELECT relationship,
       orphan_rows,
       CASE WHEN orphan_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS check_result
FROM orphans
ORDER BY relationship;
GO

/* =====================================================================
   PART 3-B : Parents without children
   Question : which parent rows have NO matching child rows?
              An INNER JOIN would silently drop them.
   Grain    : one row per check
   Expected : (measured with pandas)
       customers without orders          0
       orders without any item row     775
       orders without any payment row    1
       orders without any review row   768
       products never sold               0
       sellers without any item row      0
   ===================================================================== */
SELECT 'customers without orders' AS check_name, COUNT(*) AS row_count, 0 AS expected
FROM dbo.customers AS c
WHERE NOT EXISTS (SELECT 1 FROM dbo.orders AS o WHERE o.customer_id = c.customer_id)
UNION ALL
SELECT 'orders without any item row', COUNT(*), 775
FROM dbo.orders AS o
WHERE NOT EXISTS (SELECT 1 FROM dbo.order_items AS i WHERE i.order_id = o.order_id)
UNION ALL
SELECT 'orders without any payment row', COUNT(*), 1
FROM dbo.orders AS o
WHERE NOT EXISTS (SELECT 1 FROM dbo.order_payments AS pay WHERE pay.order_id = o.order_id)
UNION ALL
SELECT 'orders without any review row', COUNT(*), 768
FROM dbo.orders AS o
WHERE NOT EXISTS (SELECT 1 FROM dbo.order_reviews AS r WHERE r.order_id = o.order_id)
UNION ALL
SELECT 'products never sold', COUNT(*), 0
FROM dbo.products AS p
WHERE NOT EXISTS (SELECT 1 FROM dbo.order_items AS i WHERE i.product_id = p.product_id)
UNION ALL
SELECT 'sellers without any item row', COUNT(*), 0
FROM dbo.sellers AS s
WHERE NOT EXISTS (SELECT 1 FROM dbo.order_items AS i WHERE i.seller_id = s.seller_id);
GO

/* =====================================================================
   PART 3-C : Which orders have no item rows?  (by order status)
   Grain    : one row per order_status (derived table = one row per order_id
              that has at least one item)
   Expected : unavailable 603 | canceled 164 | created 5 | invoiced 2 | shipped 1
   Meaning  : orders with no items have no merchandise value. They are not
              delivered orders, so they do not affect delivered-order sales.
              They DO matter for G1 (all statuses) and A5.
   ===================================================================== */
SELECT o.order_status,
       COUNT(*) AS orders_without_items
FROM dbo.orders AS o
LEFT JOIN (SELECT DISTINCT order_id FROM dbo.order_items) AS i   -- grain: one row per order
       ON i.order_id = o.order_id
WHERE i.order_id IS NULL
GROUP BY o.order_status
ORDER BY orders_without_items DESC, o.order_status;
GO

/* =====================================================================
   PART 3-D : Coverage of DELIVERED orders in the analysis window
   Population : order_status = 'delivered' AND purchase date in
                [2017-01-01, 2018-09-01)   (start inclusive, end exclusive)
   Grain      : one summary row
   Expected   : delivered_orders 96,211 | without_items 0 | without_payments 0 |
                without_review_row 643
   Meaning    : the PDF says missing item matches must be disclosed.
                "without_review_row" = no row at all in order_reviews; whether
                the review is VALID (score 1-5) is checked in Part 4.
   ===================================================================== */
SELECT COUNT(*)              AS delivered_orders_in_window,
       SUM(d.no_items)       AS without_items,
       SUM(d.no_payments)    AS without_payments,
       SUM(d.no_review_row)  AS without_review_row
FROM (SELECT o.order_id,                                   -- grain: one row per delivered order in window
             CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.order_items i
                                   WHERE i.order_id = o.order_id) THEN 1 ELSE 0 END AS no_items,
             CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.order_payments pay
                                   WHERE pay.order_id = o.order_id) THEN 1 ELSE 0 END AS no_payments,
             CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.order_reviews r
                                   WHERE r.order_id = o.order_id) THEN 1 ELSE 0 END AS no_review_row
      FROM dbo.orders AS o
      WHERE o.order_status = 'delivered'
        AND o.order_purchase_timestamp >= '2017-01-01'
        AND o.order_purchase_timestamp <  '2018-09-01') AS d;
GO

/* =====================================================================
   PART 3-E : Product categories and the translation table
   Rule     : LEFT JOIN to category_translation so that missing categories
              stay visible (PDF, Section 4).
   Grain    : one row per check
   Expected : products with NULL category        610
              products whose category is missing in the translation  13
              distinct untranslated categories     2
                (pc_gamer, portateis_cozinha_e_preparadores_de_alimentos)
   Treatment: analysis will label them:
                NULL category        -> 'unknown'
                untranslated category-> the Portuguese name is kept
              Rows are never dropped.
   ===================================================================== */
SELECT 'products with NULL category' AS check_name,
       COUNT(*) AS value, 610 AS expected
FROM dbo.products
WHERE product_category_name IS NULL
UNION ALL
SELECT 'products with category missing in translation', COUNT(*), 13
FROM dbo.products AS p
LEFT JOIN dbo.category_translation AS t
       ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
UNION ALL
SELECT 'distinct categories missing in translation', COUNT(DISTINCT p.product_category_name), 2
FROM dbo.products AS p
LEFT JOIN dbo.category_translation AS t
       ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL;
GO

/* =====================================================================
   PART 4-A : Review scores
   Rule     : valid scores are 1-5 (PDF, Section 8).
   Grain    : one row per score value
   Expected : 1 -> 11,424 | 2 -> 3,151 | 3 -> 8,179 | 4 -> 19,142 | 5 -> 57,328
              invalid (NULL or outside 1-5) = 0
   ===================================================================== */
SELECT review_score,
       COUNT(*) AS review_rows,
       CASE WHEN review_score BETWEEN 1 AND 5 THEN 'valid' ELSE 'INVALID' END AS score_status
FROM dbo.order_reviews
GROUP BY review_score
ORDER BY review_score;
GO

/* =====================================================================
   PART 4-B : Purchase-date range and the analysis window
   Window   : 2017-01-01 <= purchase < 2018-09-01  (end date EXCLUSIVE,
              so every order on 2018-08-31 is included)
   Grain    : one summary row
   Expected : first_purchase 2016-09-04 21:15:19 | last_purchase 2018-10-17 17:30:18
              orders_in_window 99,092 | before_window 329 | after_window 20
              orders_on_2018_08_31 1
   Treatment: orders outside the window stay in the database (nothing is
              deleted); analysis queries filter on the window.
   ===================================================================== */
SELECT MIN(order_purchase_timestamp) AS first_purchase,
       MAX(order_purchase_timestamp) AS last_purchase,
       SUM(CASE WHEN order_purchase_timestamp >= '2017-01-01'
                 AND order_purchase_timestamp <  '2018-09-01' THEN 1 ELSE 0 END) AS orders_in_window,
       SUM(CASE WHEN order_purchase_timestamp <  '2017-01-01' THEN 1 ELSE 0 END) AS before_window,
       SUM(CASE WHEN order_purchase_timestamp >= '2018-09-01' THEN 1 ELSE 0 END) AS after_window,
       SUM(CASE WHEN order_purchase_timestamp >= '2018-08-31'
                 AND order_purchase_timestamp <  '2018-09-01' THEN 1 ELSE 0 END) AS orders_on_2018_08_31
FROM dbo.orders;
GO

/* =====================================================================
   PART 4-C : Date logic (impossible or missing dates)
   Grain    : one row per check
   Population: first block = ALL orders; second block = DELIVERED orders
               inside the analysis window (the population of most questions).
   Expected (measured with pandas):
       all orders  : approved before purchase            0
                     carrier date before purchase      166
                     customer delivery before purchase   0
                     customer delivery before carrier   23
                     estimated before purchase           0
                     NOT delivered but has a customer-delivery date  6
       delivered in window:
                     missing customer-delivery date      8
                     missing estimated date              0
                     customer delivery before purchase   0
                     customer delivery before carrier   19
                     valid for late-rate (both dates)  96,203
                     late (calendar-date comparison)    6,531
   Treatment:
     * Delivery days  = purchase -> actual customer delivery. A pair is
       excluded if either date is missing or delivery is before purchase.
       Exclusions are counted and reported.
     * Late = CAST(actual AS DATE) > CAST(estimated AS DATE)   (PDF rule).
     * Carrier-date anomalies are documented but do not enter any PDF metric,
       because no metric uses the carrier date. Rows are kept.
   ===================================================================== */
WITH d AS (                                   -- grain: one row per delivered order in the window
    SELECT *
    FROM dbo.orders
    WHERE order_status = 'delivered'
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp <  '2018-09-01'
)
SELECT 'ALL: approved before purchase' AS check_name, COUNT(*) AS row_count, 0 AS expected
FROM dbo.orders WHERE order_approved_at < order_purchase_timestamp
UNION ALL SELECT 'ALL: carrier date before purchase', COUNT(*), 166
FROM dbo.orders WHERE order_delivered_carrier_date < order_purchase_timestamp
UNION ALL SELECT 'ALL: customer delivery before purchase', COUNT(*), 0
FROM dbo.orders WHERE order_delivered_customer_date < order_purchase_timestamp
UNION ALL SELECT 'ALL: customer delivery before carrier date', COUNT(*), 23
FROM dbo.orders WHERE order_delivered_customer_date < order_delivered_carrier_date
UNION ALL SELECT 'ALL: estimated date before purchase', COUNT(*), 0
FROM dbo.orders WHERE order_estimated_delivery_date < order_purchase_timestamp
UNION ALL SELECT 'ALL: NOT delivered but has a customer-delivery date', COUNT(*), 6
FROM dbo.orders WHERE order_status <> 'delivered' AND order_delivered_customer_date IS NOT NULL
UNION ALL SELECT 'DELIVERED-IN-WINDOW: missing customer-delivery date', COUNT(*), 8
FROM d WHERE order_delivered_customer_date IS NULL
UNION ALL SELECT 'DELIVERED-IN-WINDOW: missing estimated date', COUNT(*), 0
FROM d WHERE order_estimated_delivery_date IS NULL
UNION ALL SELECT 'DELIVERED-IN-WINDOW: customer delivery before purchase', COUNT(*), 0
FROM d WHERE order_delivered_customer_date < order_purchase_timestamp
UNION ALL SELECT 'DELIVERED-IN-WINDOW: customer delivery before carrier date', COUNT(*), 19
FROM d WHERE order_delivered_customer_date < order_delivered_carrier_date
UNION ALL SELECT 'DELIVERED-IN-WINDOW: valid for late rate (both dates present)', COUNT(*), 96203
FROM d WHERE order_delivered_customer_date IS NOT NULL
         AND order_estimated_delivery_date IS NOT NULL
UNION ALL SELECT 'DELIVERED-IN-WINDOW: late (actual date > estimated date)', COUNT(*), 6531
FROM d WHERE CAST(order_delivered_customer_date  AS DATE)
           > CAST(order_estimated_delivery_date AS DATE);
GO

/* =====================================================================
   PART 4-D : Money and counts - negative, zero, or odd values
   Grain    : one row per check
   Expected (measured with pandas):
       item price <= 0                      0
       item freight < 0                     0
       item freight = 0                   383   (valid: free shipping or missing charge;
                                                  kept, not an error - needed for Track I)
       payment_value < 0                    0
       payment_value = 0                    9   (6 voucher + 3 not_defined)
       payment_type = 'not_defined'         3   (all with value 0.00)
       payment_installments = 0             2
   Treatment: nothing is deleted. Zero payments stay as payment records
   (they count as "has a payment record" in G3). The PDF says that missing
   or mismatching payments must not be labelled as failed payments.
   ===================================================================== */
SELECT 'order_items: price <= 0' AS check_name, COUNT(*) AS row_count, 0 AS expected
FROM dbo.order_items WHERE price <= 0
UNION ALL SELECT 'order_items: freight_value < 0', COUNT(*), 0
FROM dbo.order_items WHERE freight_value < 0
UNION ALL SELECT 'order_items: freight_value = 0', COUNT(*), 383
FROM dbo.order_items WHERE freight_value = 0
UNION ALL SELECT 'order_payments: payment_value < 0', COUNT(*), 0
FROM dbo.order_payments WHERE payment_value < 0
UNION ALL SELECT 'order_payments: payment_value = 0', COUNT(*), 9
FROM dbo.order_payments WHERE payment_value = 0
UNION ALL SELECT 'order_payments: payment_type = not_defined', COUNT(*), 3
FROM dbo.order_payments WHERE payment_type = 'not_defined'
UNION ALL SELECT 'order_payments: payment_installments = 0', COUNT(*), 2
FROM dbo.order_payments WHERE payment_installments = 0;

-- Payment types and zero-value payments by type
-- Expected: credit_card 76,795 | boleto 19,784 | voucher 5,775 | debit_card 1,529 | not_defined 3
--           zero-value rows: voucher 6, not_defined 3
SELECT payment_type,
       COUNT(*) AS payment_rows,
       SUM(CASE WHEN payment_value = 0 THEN 1 ELSE 0 END) AS zero_value_rows
FROM dbo.order_payments
GROUP BY payment_type
ORDER BY payment_rows DESC;
GO

/* =====================================================================
   PART 4-E : Product dimensions and review timestamps
   Grain    : one row per check
   Expected : weight = 0 -> 4 | length/height/width = 0 -> 0 | weight < 0 -> 0
              review answered before it was created -> 0
              order_item_id < 1 -> 0
   Treatment: weight = 0 is physically impossible, so Track-I style weight
              bands must put it in an 'invalid weight' band, separate from
              NULL (missing) weights (2 products).
   ===================================================================== */
SELECT 'products: weight = 0' AS check_name, COUNT(*) AS row_count, 4 AS expected
FROM dbo.products WHERE product_weight_g = 0
UNION ALL SELECT 'products: weight < 0', COUNT(*), 0
FROM dbo.products WHERE product_weight_g < 0
UNION ALL SELECT 'products: length/height/width = 0', COUNT(*), 0
FROM dbo.products WHERE product_length_cm = 0 OR product_height_cm = 0 OR product_width_cm = 0
UNION ALL SELECT 'order_reviews: answered before created', COUNT(*), 0
FROM dbo.order_reviews WHERE review_answer_timestamp < review_creation_date
UNION ALL SELECT 'order_items: order_item_id < 1', COUNT(*), 0
FROM dbo.order_items WHERE order_item_id < 1;
GO

/* =====================================================================
   PART 5-A : Primary keys and foreign keys
   Why now  : Parts 2-3 proved that every key is unique and that there are
              no orphan rows, so the constraints can be added safely.
   Re-runnable: each constraint is created only if it does not exist yet.
   Choices  :
     * order_reviews gets its PK on source_row_id (review_id is NOT unique).
     * NO foreign key products.product_category_name -> category_translation:
       610 products have no category and 13 have an untranslated category.
       The relationship is handled with LEFT JOIN instead.
     * Foreign keys are created WITH CHECK so SQL Server validates all rows.
   ===================================================================== */
-- Primary keys
IF OBJECT_ID(N'dbo.PK_customers', N'PK') IS NULL
    ALTER TABLE dbo.customers ADD CONSTRAINT PK_customers PRIMARY KEY (customer_id);
IF OBJECT_ID(N'dbo.PK_orders', N'PK') IS NULL
    ALTER TABLE dbo.orders ADD CONSTRAINT PK_orders PRIMARY KEY (order_id);
IF OBJECT_ID(N'dbo.PK_products', N'PK') IS NULL
    ALTER TABLE dbo.products ADD CONSTRAINT PK_products PRIMARY KEY (product_id);
IF OBJECT_ID(N'dbo.PK_sellers', N'PK') IS NULL
    ALTER TABLE dbo.sellers ADD CONSTRAINT PK_sellers PRIMARY KEY (seller_id);
IF OBJECT_ID(N'dbo.PK_category_translation', N'PK') IS NULL
    ALTER TABLE dbo.category_translation ADD CONSTRAINT PK_category_translation PRIMARY KEY (product_category_name);
IF OBJECT_ID(N'dbo.PK_order_items', N'PK') IS NULL
    ALTER TABLE dbo.order_items ADD CONSTRAINT PK_order_items PRIMARY KEY (order_id, order_item_id);
IF OBJECT_ID(N'dbo.PK_order_payments', N'PK') IS NULL
    ALTER TABLE dbo.order_payments ADD CONSTRAINT PK_order_payments PRIMARY KEY (order_id, payment_sequential);
IF OBJECT_ID(N'dbo.PK_order_reviews', N'PK') IS NULL
    ALTER TABLE dbo.order_reviews ADD CONSTRAINT PK_order_reviews PRIMARY KEY (source_row_id);
GO

-- Foreign keys (parents now have primary keys)
IF OBJECT_ID(N'dbo.FK_orders_customers', N'F') IS NULL
    ALTER TABLE dbo.orders WITH CHECK ADD CONSTRAINT FK_orders_customers
        FOREIGN KEY (customer_id) REFERENCES dbo.customers (customer_id);
IF OBJECT_ID(N'dbo.FK_order_items_orders', N'F') IS NULL
    ALTER TABLE dbo.order_items WITH CHECK ADD CONSTRAINT FK_order_items_orders
        FOREIGN KEY (order_id) REFERENCES dbo.orders (order_id);
IF OBJECT_ID(N'dbo.FK_order_items_products', N'F') IS NULL
    ALTER TABLE dbo.order_items WITH CHECK ADD CONSTRAINT FK_order_items_products
        FOREIGN KEY (product_id) REFERENCES dbo.products (product_id);
IF OBJECT_ID(N'dbo.FK_order_items_sellers', N'F') IS NULL
    ALTER TABLE dbo.order_items WITH CHECK ADD CONSTRAINT FK_order_items_sellers
        FOREIGN KEY (seller_id) REFERENCES dbo.sellers (seller_id);
IF OBJECT_ID(N'dbo.FK_order_payments_orders', N'F') IS NULL
    ALTER TABLE dbo.order_payments WITH CHECK ADD CONSTRAINT FK_order_payments_orders
        FOREIGN KEY (order_id) REFERENCES dbo.orders (order_id);
IF OBJECT_ID(N'dbo.FK_order_reviews_orders', N'F') IS NULL
    ALTER TABLE dbo.order_reviews WITH CHECK ADD CONSTRAINT FK_order_reviews_orders
        FOREIGN KEY (order_id) REFERENCES dbo.orders (order_id);
GO

/* Verification
   Grain    : one row per constraint
   Expected : 8 primary keys + 6 foreign keys, all trusted (is_not_trusted = 0)
              and enabled (is_disabled = 0). */
SELECT 'PRIMARY KEY' AS constraint_type,
       OBJECT_NAME(parent_object_id) AS table_name,
       name AS constraint_name,
       0 AS is_disabled,
       0 AS is_not_trusted
FROM sys.key_constraints
WHERE type = 'PK' AND SCHEMA_NAME(schema_id) = 'dbo'
UNION ALL
SELECT 'FOREIGN KEY',
       OBJECT_NAME(parent_object_id),
       name,
       is_disabled,
       is_not_trusted
FROM sys.foreign_keys
WHERE SCHEMA_NAME(schema_id) = 'dbo'
ORDER BY constraint_type DESC, table_name, constraint_name;
GO

/* =====================================================================
   PART 5-B : Analysis-ready views  (the "clean layer")
   Every view declares its GRAIN. Analysis queries (03_analysis.sql) read
   these views instead of the raw tables, so the window, the delivered
   filter and the one-review-per-order rule are defined in ONE place.

   View                     Grain (one row per ...)              Population
   -----------------------  -----------------------------------  ---------------------------
   vw_orders_in_scope       order                                all statuses, purchase window
   vw_delivered_orders      order                                delivered, purchase window
   vw_order_items           item row of a delivered order        delivered, purchase window
   vw_order_values          delivered order                      delivered, purchase window
   vw_order_payments        order                                every order with a payment
   vw_order_review          order                                every order with a valid review
   ===================================================================== */
GO

-- 1) Orders in the analysis window, all statuses, with their customer.
--    orders -> customers is an INNER JOIN: Part 3-A proved no order is orphaned.
CREATE OR ALTER VIEW dbo.vw_orders_in_scope AS
SELECT o.order_id,
       o.customer_id,
       c.customer_unique_id,                       -- the PERSON (PDF rule)
       c.customer_city,
       c.customer_state,
       o.order_status,
       o.order_purchase_timestamp              AS purchase_ts,
       CAST(o.order_purchase_timestamp AS DATE) AS purchase_date,
       DATEFROMPARTS(YEAR(o.order_purchase_timestamp),
                     MONTH(o.order_purchase_timestamp), 1) AS purchase_month,
       o.order_delivered_carrier_date          AS carrier_ts,
       o.order_delivered_customer_date         AS delivered_ts,
       o.order_estimated_delivery_date         AS estimated_ts
FROM dbo.orders AS o
JOIN dbo.customers AS c
  ON c.customer_id = o.customer_id
WHERE o.order_purchase_timestamp >= '2017-01-01'    -- start inclusive
  AND o.order_purchase_timestamp <  '2018-09-01';   -- end exclusive
GO

-- 2) Delivered orders + delivery metrics (PDF Section 8).
--    delivery_days : (delivered - purchase) in days, from SECONDS / 86400.0
--                    (fractional days, 2 decimals). NULL if a date is missing
--                    or delivery is before purchase.
--    is_late       : 1 if CALENDAR DATE of delivery > CALENDAR DATE of estimate.
--    delay_days    : max(0, actual date - estimated date), in calendar days.
--    has_valid_delivery_dates = 0 rows are EXCLUDED from delivery metrics and
--    must be counted (8 in the window).
CREATE OR ALTER VIEW dbo.vw_delivered_orders AS
SELECT s.*,
       f.valid_dates AS has_valid_delivery_dates,
       CASE WHEN f.valid_dates = 1
            THEN CAST(DATEDIFF(SECOND, s.purchase_ts, s.delivered_ts) / 86400.0 AS DECIMAL(10,2)) END AS delivery_days,
       CASE WHEN f.valid_dates = 1
            THEN CASE WHEN CAST(s.delivered_ts AS DATE) > CAST(s.estimated_ts AS DATE) THEN 1 ELSE 0 END END AS is_late,
       CASE WHEN f.valid_dates = 1
            THEN CASE WHEN CAST(s.delivered_ts AS DATE) > CAST(s.estimated_ts AS DATE)
                      THEN DATEDIFF(DAY, CAST(s.estimated_ts AS DATE), CAST(s.delivered_ts AS DATE))
                      ELSE 0 END END AS delay_days
FROM dbo.vw_orders_in_scope AS s
CROSS APPLY (SELECT CASE WHEN s.delivered_ts IS NOT NULL
                          AND s.estimated_ts IS NOT NULL
                          AND s.delivered_ts >= s.purchase_ts THEN 1 ELSE 0 END AS valid_dates) AS f
WHERE s.order_status = 'delivered';
GO

-- 3) Item rows of delivered orders, with a category label that never drops rows.
--    LEFT JOIN to category_translation (PDF rule). category_name =
--      English name | Portuguese name if untranslated | 'unknown' if NULL.
CREATE OR ALTER VIEW dbo.vw_order_items AS
SELECT i.order_id,
       i.order_item_id,
       i.product_id,
       i.seller_id,
       i.price,
       i.freight_value,
       COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category_name,
       CASE WHEN p.product_category_name IS NULL THEN 'missing'
            WHEN t.product_category_name IS NULL THEN 'untranslated'
            ELSE 'translated' END AS category_status,
       p.product_weight_g,
       sl.seller_state,
       d.purchase_month,
       d.purchase_date,
       d.customer_unique_id,
       d.customer_state
FROM dbo.order_items AS i
JOIN dbo.vw_delivered_orders AS d  ON d.order_id = i.order_id
JOIN dbo.products            AS p  ON p.product_id = i.product_id      -- 0 orphans (Part 3-A)
LEFT JOIN dbo.category_translation AS t ON t.product_category_name = p.product_category_name
LEFT JOIN dbo.sellers        AS sl ON sl.seller_id = i.seller_id;
GO

-- 4) Order totals from ITEMS only (never joined to payments or reviews here).
--    Merchandise value = SUM(price); freight = SUM(freight_value).
--    LEFT JOIN keeps a delivered order even if it had no item row (0 such orders).
CREATE OR ALTER VIEW dbo.vw_order_values AS
SELECT d.order_id,
       d.purchase_month,
       COALESCE(it.item_rows, 0)          AS item_rows,
       COALESCE(it.distinct_products, 0)  AS distinct_products,
       COALESCE(it.distinct_sellers, 0)   AS distinct_sellers,
       COALESCE(it.merchandise_value, 0)  AS merchandise_value,
       COALESCE(it.freight_total, 0)      AS freight_total
FROM dbo.vw_delivered_orders AS d
LEFT JOIN (SELECT order_id,                                    -- grain: one row per order
                  COUNT(*)                   AS item_rows,
                  COUNT(DISTINCT product_id) AS distinct_products,
                  COUNT(DISTINCT seller_id)  AS distinct_sellers,
                  SUM(price)                 AS merchandise_value,
                  SUM(freight_value)         AS freight_total
           FROM dbo.order_items
           GROUP BY order_id) AS it
       ON it.order_id = d.order_id;
GO

-- 5) Payment totals per order. Installments are NOT multiplied (PDF rule).
CREATE OR ALTER VIEW dbo.vw_order_payments AS
SELECT order_id,
       COUNT(*)                     AS payment_records,
       COUNT(DISTINCT payment_type) AS payment_methods,
       SUM(payment_value)           AS payment_total
FROM dbo.order_payments
GROUP BY order_id;
GO

-- 6) ONE analysis review per order (PDF Section 9).
--    Only valid scores (1-5) compete. Winner = latest review_answer_timestamp
--    (NULL counts as oldest because DESC puts NULLs last), then latest
--    review_creation_date, then greatest review_id, then greatest source_row_id.
--    valid_review_rows = how many valid source review rows the order has.
CREATE OR ALTER VIEW dbo.vw_order_review AS
SELECT order_id,
       review_id,
       source_row_id,
       review_score,
       CASE WHEN review_score <= 2 THEN 1 ELSE 0 END AS is_low_rating,
       review_creation_date,
       review_answer_timestamp,
       valid_review_rows
FROM (SELECT r.order_id, r.review_id, r.source_row_id, r.review_score,
             r.review_creation_date, r.review_answer_timestamp,
             COUNT(*) OVER (PARTITION BY r.order_id) AS valid_review_rows,
             ROW_NUMBER() OVER (PARTITION BY r.order_id
                                ORDER BY r.review_answer_timestamp DESC,
                                         r.review_creation_date    DESC,
                                         r.review_id               DESC,
                                         r.source_row_id           DESC) AS rn
      FROM dbo.order_reviews AS r
      WHERE r.review_score BETWEEN 1 AND 5) AS ranked
WHERE rn = 1;
GO

/* =====================================================================
   PART 5-C : View checks (each view must keep its declared grain)
   Expected (measured with pandas on the CSVs; money tolerance 0.01 BRL):
     vw_orders_in_scope rows = distinct orders      99,092
     vw_delivered_orders rows = distinct orders     96,211
     valid delivery dates                           96,203   (8 excluded)
     late orders (calendar-date rule)                6,531
     vw_order_values rows                           96,211
     item rows in vw_order_items and vw_order_values 109,880 (must be equal)
     merchandise sales (delivered)             13,181,027.13  (items view = values view)
     freight (delivered)                        2,192,092.88
     payment total of delivered orders         15,375,875.44
     vw_order_review rows = distinct orders         98,673
     orders with 2+ valid source reviews               547
     delivered orders with a valid analysis review  95,568   (643 without)
   ===================================================================== */
WITH checks AS (
    SELECT 'vw_orders_in_scope: rows' AS check_name,
           CAST((SELECT COUNT(*) FROM dbo.vw_orders_in_scope) AS DECIMAL(18,2)) AS actual,
           CAST(99092 AS DECIMAL(18,2)) AS expected
    UNION ALL SELECT 'vw_orders_in_scope: distinct orders',
           (SELECT COUNT(DISTINCT order_id) FROM dbo.vw_orders_in_scope), 99092
    UNION ALL SELECT 'vw_delivered_orders: rows',
           (SELECT COUNT(*) FROM dbo.vw_delivered_orders), 96211
    UNION ALL SELECT 'vw_delivered_orders: distinct orders',
           (SELECT COUNT(DISTINCT order_id) FROM dbo.vw_delivered_orders), 96211
    UNION ALL SELECT 'vw_delivered_orders: valid delivery dates',
           (SELECT SUM(has_valid_delivery_dates) FROM dbo.vw_delivered_orders), 96203
    UNION ALL SELECT 'vw_delivered_orders: late orders',
           (SELECT SUM(is_late) FROM dbo.vw_delivered_orders), 6531
    UNION ALL SELECT 'vw_order_values: rows',
           (SELECT COUNT(*) FROM dbo.vw_order_values), 96211
    UNION ALL SELECT 'vw_order_values: item rows',
           (SELECT SUM(item_rows) FROM dbo.vw_order_values), 109880
    UNION ALL SELECT 'vw_order_items: rows',
           (SELECT COUNT(*) FROM dbo.vw_order_items), 109880
    UNION ALL SELECT 'vw_order_values: merchandise sales',
           (SELECT SUM(merchandise_value) FROM dbo.vw_order_values), 13181027.13
    UNION ALL SELECT 'vw_order_items: merchandise sales',
           (SELECT SUM(price) FROM dbo.vw_order_items), 13181027.13
    UNION ALL SELECT 'vw_order_values: freight',
           (SELECT SUM(freight_total) FROM dbo.vw_order_values), 2192092.88
    UNION ALL SELECT 'payments of delivered orders: total',
           (SELECT SUM(p.payment_total)
            FROM dbo.vw_delivered_orders AS d
            JOIN dbo.vw_order_payments  AS p ON p.order_id = d.order_id), 15375875.44
    UNION ALL SELECT 'vw_order_review: rows',
           (SELECT COUNT(*) FROM dbo.vw_order_review), 98673
    UNION ALL SELECT 'vw_order_review: distinct orders',
           (SELECT COUNT(DISTINCT order_id) FROM dbo.vw_order_review), 98673
    UNION ALL SELECT 'vw_order_review: orders with 2+ valid source reviews',
           (SELECT COUNT(*) FROM dbo.vw_order_review WHERE valid_review_rows > 1), 547
    UNION ALL SELECT 'delivered orders with a valid analysis review',
           (SELECT COUNT(*)
            FROM dbo.vw_delivered_orders AS d
            JOIN dbo.vw_order_review     AS r ON r.order_id = d.order_id), 95568
)
SELECT check_name,
       actual,
       expected,
       CASE WHEN ABS(actual - expected) <= 0.01 THEN 'PASS' ELSE 'FAIL' END AS check_result
FROM checks;
GO
