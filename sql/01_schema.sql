/* =====================================================================
   FILE      : sql/01_schema.sql
   PROJECT   : BI-Olist-Analytics  (Olist Brazilian E-Commerce, SQL + Excel)
   PURPOSE   : 1) Create the project database
               2) Create STAGING tables (raw text copy of the 8 CSV files)
               3) Import the CSV files with BULK INSERT
               4) Create TYPED tables (dbo.*) and fill them from staging
   RUN ORDER : 01_schema.sql  ->  02_validation.sql  ->  03_analysis.sql
               ->  04_dashboard_exports.sql
   PLATFORM  : SQL Server 2017 or later (needs BULK INSERT ... FORMAT='CSV')
   STATUS    : GENERATED CODE - NOT YET TESTED ON A REAL SQL SERVER.
               Run it, then compare the row counts printed at the end.

   BEFORE YOU RUN
   --------------
   1. Put the ORIGINAL, UNCHANGED CSV files in one folder (data/raw).
      Never open and save them in Excel.
   2. The folder must be readable by the SQL Server SERVICE account,
      because BULK INSERT is executed by the server, not by SSMS.
      (If SQL Server is on your own PC, a folder like C:\olist_raw\ works.)
   3. Edit ONLY the line  SET @DataPath = ...  in section 3 below.
      Keep the trailing backslash.

   DESIGN DECISIONS
   ----------------
   * Staging = every column is text. Nothing can fail on import, so the
     row counts always match the source. Conversion happens afterwards.
   * Typed tables are created WITHOUT primary/foreign keys here. The PDF
     says to test keys and unmatched join keys BEFORE adding constraints,
     so the constraints are added in 02_validation.sql.
   * Column names keep the source spelling (e.g. product_name_lenght)
     so nothing is silently renamed.
   * Blank text -> NULL, using NULLIF(LTRIM(RTRIM(x)), '').
     (Review comments use a binary-collation comparison instead, so that
     emoji-only comments are kept - see section 5.)
     Bad numbers/dates -> NULL through TRY_CONVERT (they are counted
     in 02_validation.sql, never dropped silently).
   * order_reviews keeps ALL source rows plus source_row_id (the position
     in the CSV file), needed later to break ties when choosing ONE
     review per order.
   ===================================================================== */

SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------
   1. DATABASE
   --------------------------------------------------------------------- */
IF DB_ID(N'OlistBI') IS NULL
    CREATE DATABASE OlistBI;
GO
USE OlistBI;
GO

/* ---------------------------------------------------------------------
   2. STAGING TABLES  (schema stg) - raw text, one table per CSV file
   --------------------------------------------------------------------- */
IF SCHEMA_ID(N'stg') IS NULL EXEC (N'CREATE SCHEMA stg');
GO

DROP TABLE IF EXISTS stg.customers;
CREATE TABLE stg.customers (
    customer_id               NVARCHAR(100),
    customer_unique_id        NVARCHAR(100),
    customer_zip_code_prefix  NVARCHAR(100),
    customer_city             NVARCHAR(200),
    customer_state            NVARCHAR(100)
);

DROP TABLE IF EXISTS stg.orders;
CREATE TABLE stg.orders (
    order_id                       NVARCHAR(100),
    customer_id                    NVARCHAR(100),
    order_status                   NVARCHAR(100),
    order_purchase_timestamp       NVARCHAR(100),
    order_approved_at              NVARCHAR(100),
    order_delivered_carrier_date   NVARCHAR(100),
    order_delivered_customer_date  NVARCHAR(100),
    order_estimated_delivery_date  NVARCHAR(100)
);

DROP TABLE IF EXISTS stg.order_items;
CREATE TABLE stg.order_items (
    order_id             NVARCHAR(100),
    order_item_id        NVARCHAR(100),
    product_id           NVARCHAR(100),
    seller_id            NVARCHAR(100),
    shipping_limit_date  NVARCHAR(100),
    price                NVARCHAR(100),
    freight_value        NVARCHAR(100)
);

DROP TABLE IF EXISTS stg.products;
CREATE TABLE stg.products (
    product_id                  NVARCHAR(100),
    product_category_name       NVARCHAR(200),
    product_name_lenght         NVARCHAR(100),
    product_description_lenght  NVARCHAR(100),
    product_photos_qty          NVARCHAR(100),
    product_weight_g            NVARCHAR(100),
    product_length_cm           NVARCHAR(100),
    product_height_cm           NVARCHAR(100),
    product_width_cm            NVARCHAR(100)
);

DROP TABLE IF EXISTS stg.sellers;
CREATE TABLE stg.sellers (
    seller_id               NVARCHAR(100),
    seller_zip_code_prefix  NVARCHAR(100),
    seller_city             NVARCHAR(200),
    seller_state            NVARCHAR(100)
);

DROP TABLE IF EXISTS stg.order_payments;
CREATE TABLE stg.order_payments (
    order_id              NVARCHAR(100),
    payment_sequential    NVARCHAR(100),
    payment_type          NVARCHAR(100),
    payment_installments  NVARCHAR(100),
    payment_value         NVARCHAR(100)
);

/* Reviews: review text can contain commas, quotes and line breaks, so
   the comment columns are NVARCHAR(MAX).
   source_row_id is an IDENTITY: it numbers the rows in the order they are
   read from the file (1 = first data row). BULK INSERT cannot fill an
   identity column from a CSV, so we load through a VIEW that hides it. */
DROP VIEW  IF EXISTS stg.vw_order_reviews_load;
DROP TABLE IF EXISTS stg.order_reviews;
CREATE TABLE stg.order_reviews (
    source_row_id            INT IDENTITY(1,1) NOT NULL,
    review_id                NVARCHAR(100),
    order_id                 NVARCHAR(100),
    review_score             NVARCHAR(100),
    review_comment_title     NVARCHAR(MAX),
    review_comment_message   NVARCHAR(MAX),
    review_creation_date     NVARCHAR(100),
    review_answer_timestamp  NVARCHAR(100)
);
GO
CREATE VIEW stg.vw_order_reviews_load AS
    SELECT review_id, order_id, review_score, review_comment_title,
           review_comment_message, review_creation_date, review_answer_timestamp
    FROM   stg.order_reviews;
GO

DROP TABLE IF EXISTS stg.category_translation;
CREATE TABLE stg.category_translation (
    product_category_name          NVARCHAR(200),
    product_category_name_english  NVARCHAR(200)
);
GO

/* ---------------------------------------------------------------------
   3. IMPORT THE 8 CSV FILES  (BULK INSERT)
   ---------------------------------------------------------------------
   Options used (record these in the README, as the PDF requires):
     FORMAT       = 'CSV'   -> understands quoted fields, so commas and
                               line breaks inside review text are safe
     FIELDQUOTE   = '"'     -> quote character of the files
     FIRSTROW     = 2       -> skip the header row
     ROWTERMINATOR          -> NOT the same for every file (checked on the files):
                               LF   (0x0a)   : customers, orders, order_items,
                                               products, sellers, order_payments
                               CRLF (0x0d0a) : order_reviews, category_translation
                               A wrong terminator leaves a hidden CR character
                               at the end of the last column of every row.
     CODEPAGE     = '65001' -> UTF-8 (Portuguese accents in review text)
     TABLOCK                -> faster load
   The category_translation file starts with a UTF-8 BOM; this only affects
   the header line, which FIRSTROW = 2 skips.
   --------------------------------------------------------------------- */
DECLARE @DataPath NVARCHAR(400) = N'C:\olist_raw\';   -- <<< EDIT THIS LINE ONLY

DECLARE @imports TABLE (
    id         INT IDENTITY(1,1),
    target     NVARCHAR(200),
    csv_file   NVARCHAR(200),
    row_term   NVARCHAR(10)          -- 0x0a = LF, 0x0d0a = CRLF
);
INSERT INTO @imports (target, csv_file, row_term) VALUES
 (N'stg.customers',                N'olist_customers_dataset.csv',          N'0x0a'),
 (N'stg.orders',                   N'olist_orders_dataset.csv',             N'0x0a'),
 (N'stg.order_items',              N'olist_order_items_dataset.csv',        N'0x0a'),
 (N'stg.products',                 N'olist_products_dataset.csv',           N'0x0a'),
 (N'stg.sellers',                  N'olist_sellers_dataset.csv',            N'0x0a'),
 (N'stg.order_payments',           N'olist_order_payments_dataset.csv',     N'0x0a'),
 (N'stg.vw_order_reviews_load',    N'olist_order_reviews_dataset.csv',      N'0x0d0a'),
 (N'stg.category_translation',     N'product_category_name_translation.csv',N'0x0d0a');

-- Make the script re-runnable: empty staging first (TRUNCATE also resets the identity).
TRUNCATE TABLE stg.customers;
TRUNCATE TABLE stg.orders;
TRUNCATE TABLE stg.order_items;
TRUNCATE TABLE stg.products;
TRUNCATE TABLE stg.sellers;
TRUNCATE TABLE stg.order_payments;
TRUNCATE TABLE stg.order_reviews;
TRUNCATE TABLE stg.category_translation;

DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @imports);
DECLARE @target NVARCHAR(200), @file NVARCHAR(200), @term NVARCHAR(10), @sql NVARCHAR(MAX);

WHILE @i <= @n
BEGIN
    SELECT @target = target, @file = csv_file, @term = row_term FROM @imports WHERE id = @i;

    SET @sql = N'BULK INSERT ' + @target
             + N' FROM ''' + @DataPath + @file + N''''
             + N' WITH (FORMAT = ''CSV'', FIELDQUOTE = ''"'', FIRSTROW = 2,'
             + N' ROWTERMINATOR = ''' + @term + N''', CODEPAGE = ''65001'', TABLOCK);';

    PRINT N'Loading ' + @file + N' ...';
    EXEC sys.sp_executesql @sql;
    SET @i += 1;
END;
GO

/* ---------------------------------------------------------------------
   4. TYPED TABLES (schema dbo) - same names as the PDF suggests
   Types follow the PDF: VARCHAR for IDs and zip prefixes, DECIMAL(18,2)
   for money, INT for counts/scores, DATETIME2 for timestamps.
   Text lengths are based on the longest value found in the files.
   --------------------------------------------------------------------- */
/* Drop the typed tables CHILD-FIRST. Foreign keys are added later by
   02_validation.sql (Part 5-A); a parent table cannot be dropped while a
   child table still points to it. This keeps 01_schema.sql re-runnable. */
DROP TABLE IF EXISTS dbo.order_reviews;
DROP TABLE IF EXISTS dbo.order_payments;
DROP TABLE IF EXISTS dbo.order_items;
DROP TABLE IF EXISTS dbo.orders;

DROP TABLE IF EXISTS dbo.customers;
CREATE TABLE dbo.customers (
    customer_id               VARCHAR(32)  NOT NULL,
    customer_unique_id        VARCHAR(32)  NOT NULL,
    customer_zip_code_prefix  VARCHAR(5)   NULL,
    customer_city             NVARCHAR(64) NULL,   -- longest in file: 32
    customer_state            CHAR(2)      NULL
);

DROP TABLE IF EXISTS dbo.orders;
CREATE TABLE dbo.orders (
    order_id                       VARCHAR(32)  NOT NULL,
    customer_id                    VARCHAR(32)  NOT NULL,
    order_status                   VARCHAR(20)  NOT NULL,   -- longest in file: 11
    order_purchase_timestamp       DATETIME2(0) NULL,
    order_approved_at              DATETIME2(0) NULL,
    order_delivered_carrier_date   DATETIME2(0) NULL,
    order_delivered_customer_date  DATETIME2(0) NULL,
    order_estimated_delivery_date  DATETIME2(0) NULL
);

DROP TABLE IF EXISTS dbo.order_items;
CREATE TABLE dbo.order_items (
    order_id             VARCHAR(32)   NOT NULL,
    order_item_id        INT           NOT NULL,   -- sequence inside the order, NOT a quantity
    product_id           VARCHAR(32)   NOT NULL,
    seller_id            VARCHAR(32)   NOT NULL,
    shipping_limit_date  DATETIME2(0)  NULL,
    price                DECIMAL(18,2) NULL,
    freight_value        DECIMAL(18,2) NULL
);

DROP TABLE IF EXISTS dbo.products;
CREATE TABLE dbo.products (
    product_id                  VARCHAR(32) NOT NULL,
    product_category_name       VARCHAR(64) NULL,     -- longest in file: 46
    product_name_lenght         INT NULL,             -- source spelling kept
    product_description_lenght  INT NULL,
    product_photos_qty          INT NULL,
    product_weight_g            INT NULL,
    product_length_cm           INT NULL,
    product_height_cm           INT NULL,
    product_width_cm            INT NULL
);

DROP TABLE IF EXISTS dbo.sellers;
CREATE TABLE dbo.sellers (
    seller_id               VARCHAR(32)  NOT NULL,
    seller_zip_code_prefix  VARCHAR(5)   NULL,
    seller_city             NVARCHAR(64) NULL,        -- longest in file: 40
    seller_state            CHAR(2)      NULL
);

DROP TABLE IF EXISTS dbo.order_payments;
CREATE TABLE dbo.order_payments (
    order_id              VARCHAR(32)   NOT NULL,
    payment_sequential    INT           NOT NULL,
    payment_type          VARCHAR(20)   NULL,         -- longest in file: 11
    payment_installments  INT           NULL,
    payment_value         DECIMAL(18,2) NULL
);

DROP TABLE IF EXISTS dbo.order_reviews;
CREATE TABLE dbo.order_reviews (
    source_row_id            INT           NOT NULL,  -- row position in the CSV (tie-breaker)
    review_id                VARCHAR(32)   NOT NULL,  -- NOT unique in the source
    order_id                 VARCHAR(32)   NOT NULL,
    review_score             INT           NULL,      -- valid scores are 1-5 (checked in 02)
    review_comment_title     NVARCHAR(200) NULL,
    review_comment_message   NVARCHAR(MAX) NULL,
    review_creation_date     DATETIME2(0)  NULL,
    review_answer_timestamp  DATETIME2(0)  NULL
);

DROP TABLE IF EXISTS dbo.category_translation;
CREATE TABLE dbo.category_translation (
    product_category_name          VARCHAR(64)  NOT NULL,
    product_category_name_english  VARCHAR(64)  NOT NULL
);
GO

/* ---------------------------------------------------------------------
   5. FILL TYPED TABLES FROM STAGING
   NULLIF(LTRIM(RTRIM(x)), '') turns blank text into NULL.
   TRY_CONVERT returns NULL instead of an error when a value cannot be
   converted; 02_validation.sql counts those cases.
   --------------------------------------------------------------------- */
INSERT INTO dbo.customers
SELECT NULLIF(LTRIM(RTRIM(customer_id)), ''),
       NULLIF(LTRIM(RTRIM(customer_unique_id)), ''),
       NULLIF(LTRIM(RTRIM(customer_zip_code_prefix)), ''),
       NULLIF(LTRIM(RTRIM(customer_city)), ''),
       NULLIF(LTRIM(RTRIM(customer_state)), '')
FROM stg.customers;

INSERT INTO dbo.orders
SELECT NULLIF(LTRIM(RTRIM(order_id)), ''),
       NULLIF(LTRIM(RTRIM(customer_id)), ''),
       NULLIF(LTRIM(RTRIM(order_status)), ''),
       TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_purchase_timestamp)), '')),
       TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_approved_at)), '')),
       TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_delivered_carrier_date)), '')),
       TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_delivered_customer_date)), '')),
       TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_estimated_delivery_date)), ''))
FROM stg.orders;

INSERT INTO dbo.order_items
SELECT NULLIF(LTRIM(RTRIM(order_id)), ''),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(order_item_id)), '')),
       NULLIF(LTRIM(RTRIM(product_id)), ''),
       NULLIF(LTRIM(RTRIM(seller_id)), ''),
       TRY_CONVERT(DATETIME2(0),  NULLIF(LTRIM(RTRIM(shipping_limit_date)), '')),
       TRY_CONVERT(DECIMAL(18,2), NULLIF(LTRIM(RTRIM(price)), '')),
       TRY_CONVERT(DECIMAL(18,2), NULLIF(LTRIM(RTRIM(freight_value)), ''))
FROM stg.order_items;

INSERT INTO dbo.products
SELECT NULLIF(LTRIM(RTRIM(product_id)), ''),
       NULLIF(LTRIM(RTRIM(product_category_name)), ''),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(product_name_lenght)), '')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(product_description_lenght)), '')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(product_photos_qty)), '')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(product_weight_g)), '')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(product_length_cm)), '')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(product_height_cm)), '')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(product_width_cm)), ''))
FROM stg.products;

INSERT INTO dbo.sellers
SELECT NULLIF(LTRIM(RTRIM(seller_id)), ''),
       NULLIF(LTRIM(RTRIM(seller_zip_code_prefix)), ''),
       NULLIF(LTRIM(RTRIM(seller_city)), ''),
       NULLIF(LTRIM(RTRIM(seller_state)), '')
FROM stg.sellers;

INSERT INTO dbo.order_payments
SELECT NULLIF(LTRIM(RTRIM(order_id)), ''),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(payment_sequential)), '')),
       NULLIF(LTRIM(RTRIM(payment_type)), ''),
       TRY_CONVERT(INT,           NULLIF(LTRIM(RTRIM(payment_installments)), '')),
       TRY_CONVERT(DECIMAL(18,2), NULLIF(LTRIM(RTRIM(payment_value)), ''))
FROM stg.order_payments;

INSERT INTO dbo.order_reviews
SELECT source_row_id,
       NULLIF(LTRIM(RTRIM(review_id)), ''),
       NULLIF(LTRIM(RTRIM(order_id)), ''),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(review_score)), '')),
       -- Binary collation on purpose: with the default collation an emoji-only
       -- comment (e.g. N'👍') compares EQUAL to N'' and would wrongly become NULL.
       CASE WHEN LTRIM(RTRIM(review_comment_title))   COLLATE Latin1_General_100_BIN2 = N'' THEN NULL
            ELSE LTRIM(RTRIM(review_comment_title))   END,
       CASE WHEN LTRIM(RTRIM(review_comment_message)) COLLATE Latin1_General_100_BIN2 = N'' THEN NULL
            ELSE LTRIM(RTRIM(review_comment_message)) END,
       TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(review_creation_date)), '')),
       TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(review_answer_timestamp)), ''))
FROM stg.order_reviews;

INSERT INTO dbo.category_translation
SELECT NULLIF(LTRIM(RTRIM(product_category_name)), ''),
       NULLIF(LTRIM(RTRIM(product_category_name_english)), '')
FROM stg.category_translation;
GO

/* ---------------------------------------------------------------------
   6. ROW-COUNT CHECK  (source CSV vs staging vs typed table)
   "Expected" = rows counted in the original CSV files with Python/pandas
   (CSV-aware, so review text with line breaks is counted correctly).
   Every row must say PASS.
   --------------------------------------------------------------------- */
WITH expected AS (
    SELECT 'customers'            AS table_name, 99441  AS expected_rows UNION ALL
    SELECT 'orders',                              99441  UNION ALL
    SELECT 'order_items',                         112650 UNION ALL
    SELECT 'products',                            32951  UNION ALL
    SELECT 'sellers',                             3095   UNION ALL
    SELECT 'order_payments',                      103886 UNION ALL
    SELECT 'order_reviews',                       99224  UNION ALL
    SELECT 'category_translation',                71
), actual AS (
    SELECT 'customers' AS table_name, (SELECT COUNT(*) FROM stg.customers) AS staging_rows, (SELECT COUNT(*) FROM dbo.customers) AS typed_rows UNION ALL
    SELECT 'orders',               (SELECT COUNT(*) FROM stg.orders),               (SELECT COUNT(*) FROM dbo.orders) UNION ALL
    SELECT 'order_items',          (SELECT COUNT(*) FROM stg.order_items),          (SELECT COUNT(*) FROM dbo.order_items) UNION ALL
    SELECT 'products',             (SELECT COUNT(*) FROM stg.products),             (SELECT COUNT(*) FROM dbo.products) UNION ALL
    SELECT 'sellers',              (SELECT COUNT(*) FROM stg.sellers),              (SELECT COUNT(*) FROM dbo.sellers) UNION ALL
    SELECT 'order_payments',       (SELECT COUNT(*) FROM stg.order_payments),       (SELECT COUNT(*) FROM dbo.order_payments) UNION ALL
    SELECT 'order_reviews',        (SELECT COUNT(*) FROM stg.order_reviews),        (SELECT COUNT(*) FROM dbo.order_reviews) UNION ALL
    SELECT 'category_translation', (SELECT COUNT(*) FROM stg.category_translation), (SELECT COUNT(*) FROM dbo.category_translation)
)
SELECT e.table_name,
       e.expected_rows,
       a.staging_rows,
       a.typed_rows,
       CASE WHEN e.expected_rows = a.staging_rows
             AND e.expected_rows = a.typed_rows THEN 'PASS' ELSE 'FAIL' END AS check_result
FROM expected AS e
JOIN actual   AS a ON a.table_name = e.table_name
ORDER BY e.table_name;
GO
