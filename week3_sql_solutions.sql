-- Q3.1  Quarterly Sales vs Budget  (SQL Server)
DROP TABLE IF EXISTS sales_lines;
DROP TABLE IF EXISTS category_budget;

CREATE TABLE sales_lines (
    sale_id   INT PRIMARY KEY,
    sale_date DATE,
    category  VARCHAR(30),
    amount    INT
);
INSERT INTO sales_lines (sale_id, sale_date, category, amount) VALUES
(1,  '2025-01-15', 'Electronics', 5000),
(2,  '2025-02-20', 'Stationery',   800),
(3,  '2025-04-03', 'Electronics', 7000),
(4,  '2025-05-11', 'Home',        2500),
(5,  '2025-06-30', 'Stationery',   600),
(6,  '2025-07-19', 'Electronics', 6500),
(7,  '2025-08-08', 'Home',        3000),
(8,  '2025-10-01', 'Electronics', 9000),
(9,  '2025-11-15', 'Stationery',  1200),
(10, '2025-12-24', 'Home',        4000),
(11, '2025-12-26', 'Electronics', 1000);

CREATE TABLE category_budget (
    category VARCHAR(30) PRIMARY KEY,
    Q1 INT, Q2 INT, Q3 INT, Q4 INT
);
INSERT INTO category_budget (category, Q1, Q2, Q3, Q4) VALUES
('Electronics', 6000, 6000, 7000, 10000),
('Home',        1000, 2000, 3000,  4000),
('Stationery',  1000, 1000,  500,  1500);

-- Part A : one row per category, one column per quarter (0 when no sales)
SELECT category,
       SUM(CASE WHEN DATEPART(QUARTER, sale_date) = 1 THEN amount ELSE 0 END) AS Q1,
       SUM(CASE WHEN DATEPART(QUARTER, sale_date) = 2 THEN amount ELSE 0 END) AS Q2,
       SUM(CASE WHEN DATEPART(QUARTER, sale_date) = 3 THEN amount ELSE 0 END) AS Q3,
       SUM(CASE WHEN DATEPART(QUARTER, sale_date) = 4 THEN amount ELSE 0 END) AS Q4,
       SUM(amount) AS total
FROM   sales_lines
WHERE  sale_date >= '2025-01-01' AND sale_date < '2026-01-01'
GROUP BY category
ORDER BY category;

-- Part B : budget as one row per category and quarter
SELECT b.category, v.quarter, v.budget
FROM   category_budget AS b
CROSS APPLY (VALUES ('Q1', b.Q1), ('Q2', b.Q2),
                    ('Q3', b.Q3), ('Q4', b.Q4)) AS v(quarter, budget)
ORDER BY b.category, v.quarter;

-- Part C : actual vs budget with variance (actual - budget)
WITH bud AS (
    SELECT b.category, v.quarter, v.budget
    FROM   category_budget AS b
    CROSS APPLY (VALUES ('Q1', b.Q1), ('Q2', b.Q2),
                        ('Q3', b.Q3), ('Q4', b.Q4)) AS v(quarter, budget)
),
act AS (
    SELECT category,
           'Q' + CAST(DATEPART(QUARTER, sale_date) AS CHAR(1)) AS quarter,
           SUM(amount) AS actual
    FROM   sales_lines
    WHERE  sale_date >= '2025-01-01' AND sale_date < '2026-01-01'
    GROUP BY category, DATEPART(QUARTER, sale_date)
)
SELECT bud.category,
       bud.quarter,
       ISNULL(act.actual, 0)              AS actual,
       bud.budget,
       ISNULL(act.actual, 0) - bud.budget AS variance
FROM   bud
LEFT JOIN act ON act.category = bud.category AND act.quarter = bud.quarter
ORDER BY bud.category, bud.quarter;
GO

-- Q3.2  Sync the Product Master  (SQL Server)
DROP TABLE IF EXISTS product_staging;
DROP TABLE IF EXISTS product_master;

CREATE TABLE product_master (
    product_id   VARCHAR(10) PRIMARY KEY,
    product_name VARCHAR(100),
    price        INT,
    is_active    INT
);
INSERT INTO product_master VALUES
('P1', 'Wireless Mouse', 799,  1),
('P2', 'USB-C Hub',      1999, 1),
('P3', 'Notebook A5',    120,  1),
('P4', 'Gel Pen Pack',   250,  1);

CREATE TABLE product_staging (
    product_id   VARCHAR(10) PRIMARY KEY,
    product_name VARCHAR(100),
    price        INT,
    is_deleted   CHAR(1)
);
INSERT INTO product_staging VALUES
('P2', 'USB-C Hub 7-in-1', 2199, 'N'),
('P3', 'Notebook A5',      120,  'N'),
('P4', 'Gel Pen Pack',     250,  'Y'),
('P5', 'Desk Lamp',        1499, 'N'),
('P6', 'Water Bottle',     499,  'N');

-- One statement that syncs product_master (safe to run again: 2nd run changes nothing)
DECLARE @actions TABLE (product_id VARCHAR(10), action VARCHAR(10));

MERGE product_master AS t
USING product_staging AS s
   ON t.product_id = s.product_id
WHEN MATCHED AND s.is_deleted = 'Y'
     THEN DELETE
WHEN MATCHED AND s.is_deleted = 'N'
              AND (t.product_name <> s.product_name OR t.price <> s.price)
     THEN UPDATE SET t.product_name = s.product_name,
                     t.price        = s.price
WHEN NOT MATCHED BY TARGET AND s.is_deleted = 'N'
     THEN INSERT (product_id, product_name, price, is_active)
          VALUES (s.product_id, s.product_name, s.price, 1)
OUTPUT COALESCE(inserted.product_id, deleted.product_id), $action
  INTO @actions (product_id, action);

SELECT * FROM @actions ORDER BY product_id;        -- what happened to each product
SELECT * FROM product_master ORDER BY product_id;  -- final master table
GO

-- Q3.3  Keep Address History in CustomerDim  (SQL Server, SCD Type 2)
DROP TABLE IF EXISTS CustomerDim;   -- also drops trg_dim
GO

CREATE TABLE CustomerDim (
    CustomerID         INT          NOT NULL,
    CustomerName       VARCHAR(100) NOT NULL,
    [Address]          VARCHAR(200) NOT NULL,
    EffectiveStartDate DATE         NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    EffectiveEndDate   DATE         NOT NULL DEFAULT '9999-12-31',
    IsCurrent          BIT          NOT NULL DEFAULT 1
);
GO

-- existing data (inserted BEFORE the trigger is created)
INSERT INTO CustomerDim
       (CustomerID, CustomerName, [Address], EffectiveStartDate, EffectiveEndDate, IsCurrent)
VALUES (1, 'John Doe',      '123 Main St', '2023-01-01', '9999-12-31', 1),
       (2, 'Alice Johnson', '456 Elm St',  '2023-01-01', '9999-12-31', 1),
       (3, 'Bob Smith',     '789 Oak St',  '2023-01-01', '9999-12-31', 1);
GO

CREATE TRIGGER trg_dim
ON CustomerDim
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today DATE = CAST(GETDATE() AS DATE);

    -- 1) existing customer with a NEW address: close the current row
    UPDATE d
    SET    d.EffectiveEndDate = DATEADD(DAY, -1, @today),
           d.IsCurrent        = 0
    FROM   CustomerDim d
    JOIN   inserted i ON i.CustomerID = d.CustomerID
    WHERE  d.IsCurrent = 1
      AND  d.[Address] <> i.[Address];

    -- 2) add a current row for new customers and for customers whose row was just closed
    --    (same customer + same address = no current row missing, so nothing is added)
    INSERT INTO CustomerDim
           (CustomerID, CustomerName, [Address], EffectiveStartDate, EffectiveEndDate, IsCurrent)
    SELECT i.CustomerID, i.CustomerName, i.[Address], @today, '9999-12-31', 1
    FROM   inserted i
    WHERE  NOT EXISTS (SELECT 1 FROM CustomerDim d
                       WHERE  d.CustomerID = i.CustomerID AND d.IsCurrent = 1);
END;
GO

-- the four rows, in ONE insert statement
INSERT INTO CustomerDim (CustomerID, CustomerName, [Address])
VALUES (1, 'John Doe',      'Ajmer'),
       (4, 'David Richard', 'Mumbai'),
       (3, 'Bob Smith',     'Chennai'),
       (5, 'Eva Dsouza',    'Mumbai');
GO

SELECT * FROM CustomerDim ORDER BY CustomerID, EffectiveStartDate;
GO

-- Q3.4  Make a Slow Customer Lookup Faster  (SQL Server)
DROP TABLE IF EXISTS dbo.sales_big;

CREATE TABLE dbo.sales_big (
    order_id    INT PRIMARY KEY,          -- clustered index on order_id
    customer_id VARCHAR(6),
    order_date  DATE,
    amount      DECIMAL(10,2)
);

-- 500,000 rows
;WITH n AS (
    SELECT TOP (500000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.sales_big (order_id, customer_id, order_date, amount)
SELECT rn,
       'C' + RIGHT('0000' + CAST(rn % 5000 AS VARCHAR(4)), 4),   -- C0000 .. C4999
       DATEADD(DAY, (rn - 1) % 1095, '2023-01-01'),              -- +1 day per row, repeats every 1095
       (rn * 37) % 5000 + 99
FROM n;

-- BEFORE: switch on "Include Actual Execution Plan" (Ctrl+M), then run the query
SET STATISTICS IO ON;
SELECT order_id, order_date, amount
FROM dbo.sales_big
WHERE customer_id = 'C0042'
  AND order_date >= '2025-03-01' AND order_date < '2025-04-01';
-- plan: Clustered Index Scan, Number of Rows Read = 500,000

-- THE CHANGE: covering index on the filter columns
CREATE NONCLUSTERED INDEX IX_sales_big_customer_date
    ON dbo.sales_big (customer_id, order_date)
    INCLUDE (amount);                     -- order_id comes free (it is the clustering key)

-- AFTER: run the SAME query again and look at the new plan
SELECT order_id, order_date, amount
FROM dbo.sales_big
WHERE customer_id = 'C0042'
  AND order_date >= '2025-03-01' AND order_date < '2025-04-01';
-- plan: Index Seek (NonClustered), Number of Rows Read = 4
GO
