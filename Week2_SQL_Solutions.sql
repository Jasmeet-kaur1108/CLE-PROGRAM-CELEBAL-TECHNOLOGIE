-- Week 2 SQL Practical Questions - solutions (T-SQL / SQL Server)
-- Needs SQL Server 2017 or newer (STRING_AGG, STRING_SPLIT, CREATE OR ALTER).
IF DB_ID('EduLearn') IS NULL CREATE DATABASE EduLearn;
GO
USE EduLearn;
GO

-- ======================================================================
-- Q2.1. Books That Were Beaten by Their Adaptation
-- ======================================================================
DROP TABLE IF EXISTS book_review;
DROP TABLE IF EXISTS adaptation;
DROP TABLE IF EXISTS book;
DROP TABLE IF EXISTS author;
GO
CREATE TABLE author (author_id INT PRIMARY KEY, author_name VARCHAR(50));
CREATE TABLE book (book_id INT PRIMARY KEY, author_id INT REFERENCES author(author_id),
                   title VARCHAR(100), publish_year INT);
CREATE TABLE adaptation (book_id INT PRIMARY KEY REFERENCES book(book_id),
                         [type] VARCHAR(20), title VARCHAR(100),
                         release_year INT, rating DECIMAL(4,2));
CREATE TABLE book_review (review_id INT PRIMARY KEY, book_id INT REFERENCES book(book_id),
                          rating INT);
GO
INSERT INTO author VALUES (1,'Anita Rao'),(2,'Dev Malhotra'),(3,'Kiran Sethi'),(4,'Leela Thomas');

INSERT INTO book VALUES
(101,1,'The Monsoon Letters',2015),(102,1,'City of Lanterns',2018),
(103,2,'Code of the Hills',2012),(104,3,'The Last Tea Garden',2019),
(105,4,'Silent Harbour',2016),(106,2,'Paper Kites',2020);

INSERT INTO adaptation VALUES
(101,'Movie','Monsoon Letters',2017,8.10),(102,'Series','Lanterns',2024,7.90),
(103,'Movie','Hill Code',2014,7.00),(104,'Series','Tea Garden',2022,8.60),
(105,'Movie','Harbour',2018,6.50),(106,'Movie','Kites',2021,7.40);

INSERT INTO book_review VALUES
(1,101,7),(2,101,8),(3,102,6),(4,102,7),(5,103,8),(6,103,7),(7,103,9),
(8,104,8),(9,104,8),(10,105,6),(11,105,7),(12,106,7),(13,106,7),(14,106,7);
GO
-- QUERY
SELECT b.title            AS book_title,
       a.title            AS adaptation_title,
       a.release_year     AS adaptation_year,
       b.publish_year     AS publication_year,
       au.author_name,
       r.book_rating,
       a.rating           AS adaptation_rating
FROM book b
JOIN author au     ON au.author_id = b.author_id
JOIN adaptation a  ON a.book_id    = b.book_id
JOIN (SELECT book_id,
             CAST(AVG(CAST(rating AS DECIMAL(5,2))) AS DECIMAL(4,2)) AS book_rating
      FROM book_review
      GROUP BY book_id) r ON r.book_id = b.book_id
WHERE r.book_rating < a.rating
  AND a.release_year - b.publish_year <= 4
ORDER BY b.title;

GO

-- ======================================================================
-- Q2.2. Customer Order Lookup (Function + Stored Procedure)
-- ======================================================================
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;
GO
CREATE TABLE customers (customer_id VARCHAR(10) PRIMARY KEY, customer_name VARCHAR(50),
                        city VARCHAR(50), signup_date DATE);
CREATE TABLE orders (order_id INT PRIMARY KEY,
                     customer_id VARCHAR(10) REFERENCES customers(customer_id),
                     order_date DATE, status VARCHAR(20));
CREATE TABLE order_items (order_id INT REFERENCES orders(order_id), product_id VARCHAR(10),
                          qty INT, unit_price INT, PRIMARY KEY (order_id, product_id));
GO
INSERT INTO customers VALUES
('C01','Rahul Mehta','Jaipur','2025-11-02'),('C02','Priya Nair','Kochi','2025-12-15'),
('C03','Arjun Das','Kolkata','2026-01-08'),('C04','Fatima Sheikh','Mumbai','2026-01-20'),
('C05','Karan Malhotra','Delhi','2026-02-11'),('C06','Sneha Kulkarni','Pune','2026-02-25');

INSERT INTO orders VALUES
(1001,'C01','2026-03-02','Delivered'),(1002,'C02','2026-03-03','Delivered'),
(1003,'C01','2026-03-10','Delivered'),(1004,'C03','2026-03-12','Cancelled'),
(1005,'C04','2026-03-15','Shipped'),(1006,'C05','2026-03-18','Delivered'),
(1007,'C01','2026-04-01','Shipped'),(1008,'C06','2026-04-03','Pending');

INSERT INTO order_items VALUES
(1001,'P1',2,799),(1001,'P3',5,120),(1002,'P2',1,1999),(1003,'P4',2,250),
(1003,'P6',1,499),(1004,'P5',1,1499),(1005,'P1',1,799),(1005,'P2',1,1999),
(1005,'P3',10,120),(1006,'P6',3,499),(1007,'P5',1,1499),(1008,'P4',4,250);
GO
-- PART A : function
CREATE OR ALTER FUNCTION dbo.fn_format_us_date (@d DATETIME2)
RETURNS VARCHAR(10)
AS
BEGIN
    RETURN CONVERT(VARCHAR(10), @d, 101);      -- style 101 = MM/DD/YYYY
END;
GO
-- PART B : procedure
CREATE OR ALTER PROCEDURE dbo.sp_customer_orders
    @customer_id  VARCHAR(10),
    @order_count  INT           OUTPUT,
    @total_value  DECIMAL(10,2) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT o.order_id,
           dbo.fn_format_us_date(o.order_date)      AS order_date_us,
           o.status,
           ISNULL(SUM(oi.qty * oi.unit_price), 0)   AS order_value
    INTO #t
    FROM orders o
    LEFT JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.customer_id = @customer_id
      AND o.status <> 'Cancelled'
    GROUP BY o.order_id, o.order_date, o.status;

    SELECT order_id, order_date_us, status, order_value FROM #t ORDER BY order_id;

    SELECT @order_count = COUNT(*),
           @total_value = ISNULL(SUM(order_value), 0)
    FROM #t;
END;
GO
-- TEST (function)
SELECT dbo.fn_format_us_date('2006-11-21 23:34:05.920') AS us_date;   -- 11/21/2006
GO
-- TEST 1 : customer C01
DECLARE @cnt INT, @val DECIMAL(10,2);
EXEC dbo.sp_customer_orders @customer_id = 'C01', @order_count = @cnt OUTPUT,
                            @total_value = @val OUTPUT;
SELECT @cnt AS order_count, @val AS total_value;
GO
-- TEST 2 : customer C99 (does not exist -> no rows, 0 and 0)
DECLARE @cnt INT, @val DECIMAL(10,2);
EXEC dbo.sp_customer_orders @customer_id = 'C99', @order_count = @cnt OUTPUT,
                            @total_value = @val OUTPUT;
SELECT @cnt AS order_count, @val AS total_value;

GO

-- ======================================================================
-- Q2.3. Remaining Dates of the Month (sp_dateproc)
-- ======================================================================
DROP TABLE IF EXISTS datepro_data;
DROP TABLE IF EXISTS datepro;
GO
CREATE TABLE datepro (id INT PRIMARY KEY, Dateint INT, Datentime VARCHAR(40));
CREATE TABLE datepro_data (id INT, Dateint INT, Datentime VARCHAR(20), Dates DATE);
GO
INSERT INTO datepro VALUES
(101,20220510,'2022-05-10T09:30:00+05:30'),
(102,20220227,'2022-02-27T18:45:00+05:30'),
(103,20220925,'2022-09-25T12:16:00+05:30'),
(104,20221229,'2022-12-29T07:05:00+05:30'),
(105,20221228,'2022-12-28T11:29:00+05:30');
GO
CREATE OR ALTER PROCEDURE sp_dateproc @ids VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM datepro_data;                       -- fresh run every time

    ;WITH src AS (
        SELECT d.id, d.Dateint,
               LEFT(REPLACE(d.Datentime, 'T', ' '), 16)              AS Datentime,  -- no T, no tz
               CONVERT(DATE, CAST(d.Dateint AS VARCHAR(8)), 112)     AS start_dt,
               EOMONTH(CONVERT(DATE, CAST(d.Dateint AS VARCHAR(8)), 112)) AS end_dt
        FROM datepro d
        WHERE d.id IN (SELECT CAST(value AS INT) FROM STRING_SPLIT(@ids, ','))
    ),
    cal AS (
        SELECT id, Dateint, Datentime, start_dt AS Dates, end_dt FROM src
        UNION ALL
        SELECT id, Dateint, Datentime, DATEADD(DAY, 1, Dates), end_dt
        FROM cal
        WHERE Dates < end_dt
    )
    INSERT INTO datepro_data (id, Dateint, Datentime, Dates)
    SELECT id, Dateint, Datentime, Dates
    FROM cal
    OPTION (MAXRECURSION 400);

    SELECT id, Dateint, Datentime, Dates
    FROM datepro_data
    ORDER BY id, Dates;
END;
GO
EXEC sp_dateproc '101,102,104';
GO
SELECT COUNT(*) AS total_rows FROM datepro_data;      -- 27  (22 + 2 + 3)

GO

-- ======================================================================
-- Q2.4. Open Elective Subject Allotment
-- ======================================================================
-- Note: Allotments has an extra IDENTITY column (AllotId) only to keep the allotment order; the procedure inserts just SubjectId and StudentId.
DROP TABLE IF EXISTS UnallotedStudents;
DROP TABLE IF EXISTS Allotments;
DROP TABLE IF EXISTS StudentPreference;
DROP TABLE IF EXISTS SubjectDetails;
DROP TABLE IF EXISTS StudentDetails;
GO
CREATE TABLE StudentDetails (StudentId INT PRIMARY KEY, StudentName VARCHAR(50),
                             GPA DECIMAL(4,2), Branch VARCHAR(10), Section VARCHAR(5));
CREATE TABLE SubjectDetails (SubjectId VARCHAR(10) PRIMARY KEY, SubjectName VARCHAR(100),
                             MaxSeats INT, RemainingSeats INT);
CREATE TABLE StudentPreference (StudentId INT REFERENCES StudentDetails(StudentId),
                                SubjectId VARCHAR(10) REFERENCES SubjectDetails(SubjectId),
                                Preference INT,
                                PRIMARY KEY (StudentId, SubjectId));
CREATE TABLE Allotments (AllotId INT IDENTITY(1,1), SubjectId VARCHAR(10), StudentId INT);
CREATE TABLE UnallotedStudents (StudentId INT);
GO
INSERT INTO StudentDetails VALUES
(159103036,'Mohit Agarwal',8.90,'CCE','A'),(159103037,'Rohit Agarwal',5.20,'CCE','A'),
(159103038,'Shohit Garg',7.10,'CCE','B'),(159103039,'Mrinal Malhotra',7.90,'CCE','A'),
(159103040,'Mehreet Singh',5.60,'CCE','A'),(159103041,'Arjun Tehlan',9.20,'CCE','B');

INSERT INTO SubjectDetails VALUES
('PO1491','Basics of Political Science',60,2),('PO1492','Basics of Accounting',120,1),
('PO1493','Basics of Financial Markets',90,1),('PO1494','Eco philosophy',60,1),
('PO1495','Automotive Trends',60,0);

INSERT INTO StudentPreference VALUES
(159103036,'PO1491',1),(159103036,'PO1492',2),(159103036,'PO1493',3),
(159103036,'PO1494',4),(159103036,'PO1495',5),
(159103037,'PO1494',1),(159103037,'PO1495',2),(159103037,'PO1492',3),
(159103037,'PO1491',4),(159103037,'PO1493',5),
(159103038,'PO1492',1),(159103038,'PO1491',2),(159103038,'PO1494',3),
(159103038,'PO1495',4),(159103038,'PO1493',5),
(159103039,'PO1491',1),(159103039,'PO1492',2),(159103039,'PO1495',3),
(159103039,'PO1493',4),(159103039,'PO1494',5),
(159103040,'PO1492',1),(159103040,'PO1494',2),(159103040,'PO1491',3),
(159103040,'PO1493',4),(159103040,'PO1495',5),
(159103041,'PO1491',1),(159103041,'PO1493',2),(159103041,'PO1492',3),
(159103041,'PO1494',4),(159103041,'PO1495',5);
GO
CREATE OR ALTER PROCEDURE dbo.sp_allot_subjects
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM Allotments;
    DELETE FROM UnallotedStudents;

    DECLARE @sid INT, @subj VARCHAR(10);

    -- highest GPA first
    DECLARE stu CURSOR LOCAL FAST_FORWARD FOR
        SELECT StudentId FROM StudentDetails ORDER BY GPA DESC, StudentId;

    OPEN stu;
    FETCH NEXT FROM stu INTO @sid;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @subj = NULL;

        -- best-ranked preference that still has a seat
        SELECT TOP 1 @subj = sp.SubjectId
        FROM StudentPreference sp
        JOIN SubjectDetails sd ON sd.SubjectId = sp.SubjectId
        WHERE sp.StudentId = @sid
          AND sd.RemainingSeats > 0
        ORDER BY sp.Preference;

        IF @subj IS NOT NULL
        BEGIN
            INSERT INTO Allotments (SubjectId, StudentId) VALUES (@subj, @sid);
            UPDATE SubjectDetails SET RemainingSeats = RemainingSeats - 1
            WHERE SubjectId = @subj;
        END
        ELSE
            INSERT INTO UnallotedStudents (StudentId) VALUES (@sid);

        FETCH NEXT FROM stu INTO @sid;
    END;
    CLOSE stu;
    DEALLOCATE stu;
END;
GO
EXEC dbo.sp_allot_subjects;
GO
SELECT SubjectId, StudentId FROM Allotments ORDER BY AllotId;
SELECT StudentId FROM UnallotedStudents;
SELECT * FROM SubjectDetails;

GO

-- ======================================================================
-- Q2.5. Safe Payment Posting with Error Handling
-- ======================================================================
-- Create tables and insert data (orders + order_items, same data as Q2.2)
DROP TABLE IF EXISTS error_log;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
GO
CREATE TABLE orders (order_id INT PRIMARY KEY, customer_id VARCHAR(10),
                     order_date DATE, status VARCHAR(20));
CREATE TABLE order_items (order_id INT REFERENCES orders(order_id), product_id VARCHAR(10),
                          qty INT, unit_price INT, PRIMARY KEY (order_id, product_id));
GO
INSERT INTO orders VALUES
(1001,'C01','2026-03-02','Delivered'),(1002,'C02','2026-03-03','Delivered'),
(1003,'C01','2026-03-10','Delivered'),(1004,'C03','2026-03-12','Cancelled'),
(1005,'C04','2026-03-15','Shipped'),(1006,'C05','2026-03-18','Delivered'),
(1007,'C01','2026-04-01','Shipped'),(1008,'C06','2026-04-03','Pending');

INSERT INTO order_items VALUES
(1001,'P1',2,799),(1001,'P3',5,120),(1002,'P2',1,1999),(1003,'P4',2,250),
(1003,'P6',1,499),(1004,'P5',1,1499),(1005,'P1',1,799),(1005,'P2',1,1999),
(1005,'P3',10,120),(1006,'P6',3,499),(1007,'P5',1,1499),(1008,'P4',4,250);
GO
-- Create payments + error_log, insert data, create procedure and run the six calls
CREATE TABLE payments (payment_id VARCHAR(10) PRIMARY KEY, order_id INT, payment_date DATE,
                       amount INT, method VARCHAR(20));
CREATE TABLE error_log (log_id INT IDENTITY(1,1) PRIMARY KEY,
                        error_time DATETIME DEFAULT GETDATE(),
                        proc_name VARCHAR(100), error_number INT,
                        error_message VARCHAR(500), input_values VARCHAR(500));
GO
INSERT INTO payments VALUES
('PM01',1001,'2026-03-02',2198,'UPI'),('PM02',1002,'2026-03-03',1000,'Card'),
('PM03',1002,'2026-03-05',999,'Card'),('PM04',1003,'2026-03-10',500,'UPI'),
('PM05',1005,'2026-03-15',3998,'NetBanking'),('PM06',1006,'2026-03-18',1497,'UPI'),
('PM07',1009,'2026-04-02',750,'UPI'),('PM08',1004,'2026-03-12',1499,'Card');
GO
CREATE OR ALTER PROCEDURE dbo.sp_record_payment
    @payment_id VARCHAR(10),
    @order_id   INT,
    @amount     INT,
    @method     VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @status VARCHAR(20), @order_value INT, @paid INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @status = status FROM orders WHERE order_id = @order_id;

        IF @status IS NULL        THROW 50001, 'Order not found', 1;
        IF @status = 'Cancelled'  THROW 50002, 'Order is cancelled', 1;
        IF @amount <= 0           THROW 50003, 'Amount must be greater than zero', 1;

        SELECT @order_value = ISNULL(SUM(qty * unit_price), 0)
        FROM order_items WHERE order_id = @order_id;

        SELECT @paid = ISNULL(SUM(amount), 0)
        FROM payments WHERE order_id = @order_id;

        IF @paid + @amount > @order_value
            THROW 50004, 'Payment exceeds order value', 1;

        INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
        VALUES (@payment_id, @order_id, CAST(GETDATE() AS DATE), @amount, @method);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        INSERT INTO error_log (proc_name, error_number, error_message, input_values)
        VALUES ('sp_record_payment', ERROR_NUMBER(), ERROR_MESSAGE(),
                CONCAT(@payment_id, ',', @order_id, ',', @amount, ',', @method));
    END CATCH
END;
GO
EXEC dbo.sp_record_payment 'PM09', 1007, 1499, 'Card';   -- 1 : success
EXEC dbo.sp_record_payment 'PM10', 1010,  500, 'UPI';    -- 2 : 50001
EXEC dbo.sp_record_payment 'PM11', 1004,  100, 'UPI';    -- 3 : 50002
EXEC dbo.sp_record_payment 'PM12', 1003,    0, 'UPI';    -- 4 : 50003
EXEC dbo.sp_record_payment 'PM13', 1003,  600, 'UPI';    -- 5 : 50004
EXEC dbo.sp_record_payment 'PM14', 1003,  499, 'UPI';    -- 6 : success
GO
SELECT payment_id, order_id, amount, method FROM payments WHERE payment_id >= 'PM09';
SELECT log_id, proc_name, error_number, error_message, input_values FROM error_log;

GO

-- ======================================================================
-- Q2.6. Rank Employees by Salary Within Each Department
-- ======================================================================
DROP TABLE IF EXISTS emp_salary;
GO
CREATE TABLE emp_salary (emp_id INT PRIMARY KEY, emp_name VARCHAR(50),
                         department VARCHAR(50), salary INT);
GO
INSERT INTO emp_salary VALUES
(1,'Aditi','Engineering',100000),(2,'Bharat','Engineering',100000),
(3,'Chetan','Engineering',90000),(4,'Divya','Engineering',80000),
(5,'Eshan','Engineering',80000),(6,'Farhan','Engineering',70000),
(7,'Gauri','Sales',75000),(8,'Harsh','Sales',72000),(9,'Ira','Sales',72000),
(10,'Jatin','Support',50000),(11,'Kavya','HR',60000),(12,'Lokesh','HR',60000);
GO
-- PART A
SELECT emp_id, emp_name, department, salary,
       ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC, emp_id) AS row_num,
       RANK()       OVER (PARTITION BY department ORDER BY salary DESC)         AS rnk,
       DENSE_RANK() OVER (PARTITION BY department ORDER BY salary DESC)         AS dense_rnk
FROM emp_salary
ORDER BY department, salary DESC, emp_id;
GO
-- PART B : top 3 distinct salary levels per department
WITH lvl AS (
    SELECT department, emp_id, emp_name, salary,
           DENSE_RANK() OVER (PARTITION BY department ORDER BY salary DESC) AS salary_level
    FROM emp_salary
)
SELECT department, emp_name, salary, salary_level
FROM lvl
WHERE salary_level <= 3
ORDER BY department, salary_level, emp_id;

GO

-- ======================================================================
-- Q2.7. Book and Author View with Comma-Separated Names
-- ======================================================================
-- Note: a view cannot carry an ORDER BY, so rows may come in any order; authors inside each cell are always alphabetical.
DROP VIEW  IF EXISTS vw_book_author;
DROP TABLE IF EXISTS BookAuthors;
DROP TABLE IF EXISTS Authors;
DROP TABLE IF EXISTS Books;
GO
CREATE TABLE Books (BookID INT PRIMARY KEY, Title VARCHAR(100));
CREATE TABLE Authors (AuthorID INT PRIMARY KEY, AuthorName VARCHAR(100));
CREATE TABLE BookAuthors (BookID INT REFERENCES Books(BookID),
                          AuthorID INT REFERENCES Authors(AuthorID),
                          PRIMARY KEY (BookID, AuthorID));
GO
INSERT INTO Books VALUES (1,'Desert Winds'),(2,'River Songs'),(3,'The Glass Fort'),
                         (4,'Night Train'),(5,'Salt and Stone'),(6,'Paper Moons');
INSERT INTO Authors VALUES (1,'Meera Kaul'),(2,'Rohan Sen'),(3,'Tanvi Bose'),(4,'Ishita Roy');
INSERT INTO BookAuthors VALUES (1,1),(2,2),(3,1),(3,3),(4,4),(5,2),(6,2),(6,1);
GO
CREATE OR ALTER VIEW vw_book_author
AS
WITH ac AS (                                   -- books written by each author
    SELECT AuthorID, COUNT(*) AS cnt
    FROM BookAuthors
    GROUP BY AuthorID
)
SELECT b.Title AS Booktitle,
       STRING_AGG(a.AuthorName, ',')
           WITHIN GROUP (ORDER BY a.AuthorName)                       AS Authorname,
       STRING_AGG(CAST(ac.cnt AS VARCHAR(10)), ',')
           WITHIN GROUP (ORDER BY a.AuthorName)                       AS Book_count
FROM Books b
JOIN BookAuthors ba ON ba.BookID   = b.BookID
JOIN Authors a      ON a.AuthorID  = ba.AuthorID
JOIN ac             ON ac.AuthorID = a.AuthorID
GROUP BY b.BookID, b.Title;
GO
SELECT * FROM vw_book_author;

GO

-- ======================================================================
-- Q2.8. Revised Salary and Comparison with Previously Hired Employee
-- ======================================================================
-- Note: Inc_Sal is rounded to a whole number to match the expected output.
DROP VIEW  IF EXISTS VW_EMP_DEPT;
DROP TABLE IF EXISTS Employee;
DROP TABLE IF EXISTS Dept_loc;
GO
CREATE TABLE Dept_loc (deptid INT PRIMARY KEY, deptname VARCHAR(50), loc VARCHAR(50));
CREATE TABLE Employee (Empid INT PRIMARY KEY, Full_name VARCHAR(100), Salary INT,
                       Hiredate DATE, deptid INT NULL);
GO
INSERT INTO Dept_loc VALUES (1,'HR','Dallas'),(2,'Sales','Chicago'),
       (3,'Customer service','Chicago'),(4,'IT','Boston'),(5,'Research','Seattle'),
       (6,'Legal','New York');
INSERT INTO Employee VALUES
(1012,'Raji K Nair',35500,'2018-04-09',1),(1009,'Jeena',12000,'2018-11-17',2),
(1005,'Nidhi R Shetty',10000,'2019-01-16',3),(1011,'Jiya Shetty',45500,'2019-03-27',4),
(1003,'Arun Kumar Menon',45500,'2019-08-02',5),(1007,'Farah Ali',30000,'2020-02-10',NULL),
(1001,'Manoj P Iyer',52000,'2020-07-15',2);
GO
CREATE OR ALTER VIEW VW_EMP_DEPT
AS
WITH x AS (
    SELECT e.Empid, e.Full_name, e.Salary, e.Hiredate,
           LAG(e.Salary) OVER (ORDER BY e.Hiredate) AS prev_sal,
           d.deptname, d.loc
    FROM Employee e
    LEFT JOIN Dept_loc d ON d.deptid = e.deptid
)
SELECT Empid,
       -- keep first and last word only (single names stay as they are)
       CASE WHEN CHARINDEX(' ', Full_name) = 0 THEN Full_name
            ELSE LEFT(Full_name, CHARINDEX(' ', Full_name) - 1) + ' '
                 + RIGHT(Full_name, CHARINDEX(' ', REVERSE(Full_name)) - 1)
       END AS Full_name,
       Salary,
       CAST(ROUND(CASE loc WHEN 'Chicago'  THEN Salary * 1.05
                           WHEN 'Boston'   THEN Salary * 1.03
                           WHEN 'Dallas'   THEN Salary * 1.10
                           WHEN 'New York' THEN Salary * 1.10
                           ELSE Salary END, 0) AS INT)            AS Inc_Sal,
       prev_sal                                                   AS Previous_emp_sal,
       Hiredate,
       ISNULL(deptname, 'NA')                                     AS deptname,
       ISNULL(loc, 'NA')                                          AS loc,
       CASE WHEN prev_sal IS NULL    THEN 'No previous employee'
            WHEN Salary > prev_sal   THEN 'Salary is greater than previously hired employee'
            WHEN Salary < prev_sal   THEN 'Salary is less than previously hired employee'
            ELSE 'Salary is same as previously hired employee'
       END                                                        AS message
FROM x;
GO
SELECT * FROM VW_EMP_DEPT ORDER BY Hiredate;

GO

-- ======================================================================
-- Q2.9. Running Total and 3-Month Moving Average of Revenue
-- ======================================================================
DROP TABLE IF EXISTS monthly_sales;
GO
CREATE TABLE monthly_sales (month_start DATE, region VARCHAR(20), revenue INT,
                            PRIMARY KEY (region, month_start));
GO
INSERT INTO monthly_sales VALUES
('2026-01-01','North',120000),('2026-02-01','North',135000),('2026-03-01','North',128000),
('2026-04-01','North',150000),('2026-05-01','North',160000),('2026-06-01','North',145000),
('2026-01-01','South',90000),('2026-02-01','South',85000),('2026-03-01','South',110000),
('2026-04-01','South',105000),('2026-05-01','South',130000),('2026-06-01','South',140000);
GO
SELECT region, month_start, revenue,
       SUM(revenue) OVER (PARTITION BY region ORDER BY month_start
                          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)   AS running_total,
       CAST(AVG(CAST(revenue AS DECIMAL(12,2)))
            OVER (PARTITION BY region ORDER BY month_start
                  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS DECIMAL(12,2)) AS moving_avg_3m,
       CAST(100.0 * revenue / SUM(revenue) OVER (PARTITION BY region)
            AS DECIMAL(5,2))                                                  AS pct_of_total
FROM monthly_sales
ORDER BY region, month_start;

GO

-- ======================================================================
-- Q2.10. Keep the Latest Record per Customer
-- ======================================================================
DROP TABLE IF EXISTS customer_latest;
DROP TABLE IF EXISTS customer_updates;
GO
CREATE TABLE customer_updates (load_id INT PRIMARY KEY, customer_id VARCHAR(10),
                               email VARCHAR(100), city VARCHAR(50), updated_at DATETIME2(0));
GO
INSERT INTO customer_updates VALUES
(1,'C01','rahul@mail.com','Jaipur','2026-05-01 10:00:00'),
(2,'C02','priya@mail.com','Kochi','2026-05-01 10:05:00'),
(3,'C01','rahul.m@mail.com','Jaipur','2026-05-03 09:00:00'),
(4,'C03','arjun@mail.com','Kolkata','2026-05-02 12:00:00'),
(5,'C02','priya@mail.com','Kochi','2026-05-01 10:05:00'),
(6,'C01','rahul.m@mail.com','Delhi','2026-05-03 09:00:00'),
(7,'C04','fatima@mail.com','Mumbai','2026-05-04 08:30:00'),
(8,'C03','arjun.d@mail.com','Kolkata','2026-05-05 18:45:00');
GO
-- PART A : latest row per customer (tie on updated_at -> bigger load_id)
WITH r AS (
    SELECT customer_id, email, city, updated_at, load_id,
           ROW_NUMBER() OVER (PARTITION BY customer_id
                              ORDER BY updated_at DESC, load_id DESC) AS rn
    FROM customer_updates
)
SELECT customer_id, email, city, updated_at, load_id
INTO customer_latest
FROM r
WHERE rn = 1;
GO
SELECT * FROM customer_latest ORDER BY customer_id;
GO
-- PART B : counts
SELECT (SELECT COUNT(*) FROM customer_updates)                                   AS rows_loaded,
       (SELECT COUNT(*) FROM customer_latest)                                    AS rows_kept,
       (SELECT COUNT(*) FROM customer_updates) - (SELECT COUNT(*) FROM customer_latest)
                                                                                 AS rows_removed;

GO

-- ======================================================================
-- Q2.11. Longest Login Streak per User
-- ======================================================================
DROP TABLE IF EXISTS logins;
GO
CREATE TABLE logins (user_id VARCHAR(10), login_date DATE, PRIMARY KEY (user_id, login_date));
GO
INSERT INTO logins VALUES
('U1','2026-03-01'),('U1','2026-03-02'),('U1','2026-03-03'),('U1','2026-03-05'),
('U1','2026-03-06'),('U1','2026-03-07'),
('U2','2026-03-01'),('U2','2026-03-03'),('U2','2026-03-04'),('U2','2026-03-05'),
('U2','2026-03-06'),('U2','2026-03-10'),
('U3','2026-03-02'),
('U4','2026-03-01'),('U4','2026-03-02'),('U4','2026-03-04'),('U4','2026-03-05'),
('U4','2026-03-08'),('U4','2026-03-09');
GO
WITH g AS (   -- date minus row number is constant inside a consecutive run
    SELECT user_id, login_date,
           DATEADD(DAY, -ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_date),
                   login_date) AS grp
    FROM logins
),
s AS (
    SELECT user_id, MIN(login_date) AS streak_start, MAX(login_date) AS streak_end,
           COUNT(*) AS streak_days
    FROM g
    GROUP BY user_id, grp
),
r AS (        -- longest first; on a tie the latest streak wins
    SELECT *, ROW_NUMBER() OVER (PARTITION BY user_id
                                 ORDER BY streak_days DESC, streak_start DESC) AS rn
    FROM s
)
SELECT user_id, streak_start, streak_end, streak_days
FROM r
WHERE rn = 1
ORDER BY user_id;

GO
