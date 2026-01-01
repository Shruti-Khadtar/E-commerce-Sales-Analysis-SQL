-- Create database
IF DB_ID(N'ECommerceDB') IS NULL
BEGIN
    CREATE DATABASE ECommerceDB;
END
GO

USE ECommerceDB;
GO

-- Categories (lookup)
CREATE TABLE dbo.Categories (
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName NVARCHAR(100) NOT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- Products
CREATE TABLE dbo.Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(200) NOT NULL,
    CategoryID INT NULL REFERENCES dbo.Categories(CategoryID),
    Price DECIMAL(10,2) NOT NULL,
    Cost DECIMAL(10,2) NOT NULL,
    StockQty INT NOT NULL DEFAULT 0,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- Customers
CREATE TABLE dbo.Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    Email NVARCHAR(255) UNIQUE,
    Phone NVARCHAR(20),
    City NVARCHAR(100),
    Country NVARCHAR(100),
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- Orders
CREATE TABLE dbo.Orders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES dbo.Customers(CustomerID),
   OrderDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    OrderStatus NVARCHAR(50) NOT NULL DEFAULT 'Pending',
    ShippingAddress NVARCHAR(400),
    BillingAddress NVARCHAR(400),
    ShippingCost DECIMAL(10,2) DEFAULT 0,
    Discount DECIMAL(10,2) DEFAULT 0,
    TotalAmount DECIMAL(12,2) NOT NULL DEFAULT 0 -- maintained after inserts
);
GO

-- OrderItems (line items)
CREATE TABLE dbo.OrderItems (
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL REFERENCES dbo.Orders(OrderID),
    ProductID INT NOT NULL REFERENCES dbo.Products(ProductID),
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL,
    LineTotal AS (Quantity * UnitPrice) PERSISTED
);
GO

-- Payments
CREATE TABLE dbo.Payments (
    PaymentID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL REFERENCES dbo.Orders(OrderID),
    PaymentDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    Amount DECIMAL(12,2) NOT NULL,
    PaymentMethod NVARCHAR(50),
    Status NVARCHAR(50) DEFAULT 'Completed'
);
GO

SELECT * FROM dbo.Categories

USE ECommerceDB;


-- Categories
INSERT INTO dbo.Categories (CategoryName) VALUES
('Electronics'), ('Home & Kitchen'), ('Books');
GO

-- Products
INSERT INTO dbo.Products (ProductName, CategoryID, Price, Cost, StockQty) VALUES
('Wireless Mouse', 1, 599.00, 300.00, 150),
('Bluetooth Headphones', 1, 1599.00, 900.00, 80),
('Coffee Maker', 2, 3499.00, 2100.00, 40),
('Stainless Steel Kettle', 2, 1299.00, 700.00, 60),
('Learn SQL Book', 3, 499.00, 150.00, 200);
GO

-- Customers
INSERT INTO dbo.Customers (FirstName, LastName, Email, Phone, City, Country) VALUES
('Asha','Patil','asha.patil@example.com','+91-9876500001','Pune','India'),
('Ravi','Kumar','ravi.kumar@example.com','+91-9876500002','Mumbai','India'),
('Priya','Desai','priya.desai@example.com','+91-9876500003','Nagpur','India');
GO

-- Simple Orders + Items (transactionally)
BEGIN TRAN;

INSERT INTO dbo.Orders (CustomerID, ShippingAddress, BillingAddress, ShippingCost, Discount)
VALUES (1, '12 MG Road, Pune','12 MG Road, Pune', 50.00, 0.00);
DECLARE @OID1 INT = SCOPE_IDENTITY();

INSERT INTO dbo.OrderItems (OrderID, ProductID, Quantity, UnitPrice)
VALUES (@OID1, 1, 2, 599.00), (@OID1, 5, 1, 499.00);

UPDATE dbo.Orders
SET TotalAmount = (SELECT SUM(LineTotal) FROM dbo.OrderItems WHERE OrderID = @OID1) + ShippingCost - Discount
WHERE OrderID = @OID1;

COMMIT;
GO

-- Another order
BEGIN TRAN;
INSERT INTO dbo.Orders (CustomerID, ShippingAddress, BillingAddress, ShippingCost, Discount)
VALUES (2, '45 Marine Drive, Mumbai','45 Marine Drive, Mumbai', 30.00, 50.00);
DECLARE @OID2 INT = SCOPE_IDENTITY();
INSERT INTO dbo.OrderItems (OrderID, ProductID, Quantity, UnitPrice)
VALUES (@OID2, 2, 1, 1599.00), (@OID2, 4, 1, 1299.00);
UPDATE dbo.Orders
SET TotalAmount = (SELECT SUM(LineTotal) FROM dbo.OrderItems WHERE OrderID = @OID2) + ShippingCost - Discount
WHERE OrderID = @OID2;
COMMIT;
GO



-- missing emails
SELECT * FROM dbo.Customers WHERE Email IS NULL OR LTRIM(RTRIM(Email)) = '';

-- duplicate customers by email
SELECT Email, COUNT(*) cnt FROM dbo.Customers GROUP BY Email HAVING COUNT(*) > 1;

-- negative prices / costs
SELECT * FROM dbo.Products WHERE Price <= 0 OR Cost < 0;


-- Best-selling products (by units)
SELECT p.ProductID, p.ProductName, SUM(oi.Quantity) AS TotalUnitsSold
FROM dbo.OrderItems oi
JOIN dbo.Products p ON p.ProductID = oi.ProductID
GROUP BY p.ProductID, p.ProductName
ORDER BY TotalUnitsSold DESC;

-- Revenue per month (trend)
SELECT YEAR(o.OrderDate) AS [Year], MONTH(o.OrderDate) AS [Month],
       SUM(oi.LineTotal) AS Revenue
FROM dbo.Orders o
JOIN dbo.OrderItems oi ON oi.OrderID = o.OrderID
GROUP BY YEAR(o.OrderDate), MONTH(o.OrderDate)
ORDER BY [Year], [Month];

-- Top customers by Lifetime Value (LTV)
SELECT c.CustomerID, c.FirstName, c.LastName, c.Email,
       SUM(oi.LineTotal) AS LifetimeValue
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
JOIN dbo.OrderItems oi ON oi.OrderID = o.OrderID
GROUP BY c.CustomerID, c.FirstName, c.LastName, c.Email
ORDER BY LifetimeValue DESC;

-- Profit by category
SELECT ISNULL(cat.CategoryName,'(Uncategorized)') AS CategoryName,
       SUM((oi.UnitPrice - p.Cost) * oi.Quantity) AS TotalProfit
FROM dbo.OrderItems oi
JOIN dbo.Products p ON p.ProductID = oi.ProductID
LEFT JOIN dbo.Categories cat ON cat.CategoryID = p.CategoryID
GROUP BY cat.CategoryName
ORDER BY TotalProfit DESC;


-- Average Order Value (AOV)
SELECT AVG(OrderTotal) AS AvgOrderValue
FROM (
    SELECT o.OrderID, SUM(oi.LineTotal) AS OrderTotal
    FROM dbo.Orders o
    JOIN dbo.OrderItems oi ON oi.OrderID = o.OrderID
    GROUP BY o.OrderID
) t;

-- Customers with no orders (potential targets)
SELECT * FROM dbo.Customers c
WHERE NOT EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID);



-- View: OrderDetails (flattened)
CREATE VIEW dbo.vw_OrderDetails
AS
SELECT o.OrderID, o.OrderDate, o.CustomerID, c.FirstName, c.LastName, c.Email,
       oi.OrderItemID, oi.ProductID, p.ProductName, p.CategoryID, oi.Quantity, oi.UnitPrice, oi.LineTotal,
       o.ShippingCost, o.Discount, o.TotalAmount
FROM dbo.Orders o
JOIN dbo.Customers c ON c.CustomerID = o.CustomerID
JOIN dbo.OrderItems oi ON oi.OrderID = o.OrderID
JOIN dbo.Products p ON p.ProductID = oi.ProductID;
GO

-- Stored procedure: Top N customers
CREATE PROCEDURE dbo.usp_GetTopCustomers
    @TopN INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP(@TopN) c.CustomerID, c.FirstName, c.LastName, c.Email,
           SUM(oi.LineTotal) AS LifetimeValue
    FROM dbo.Customers c
    JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
    JOIN dbo.OrderItems oi ON oi.OrderID = o.OrderID
    GROUP BY c.CustomerID, c.FirstName, c.LastName, c.Email
    ORDER BY LifetimeValue DESC;
END
GO

-- Stored procedure: Monthly revenue for a year
CREATE PROCEDURE dbo.usp_GetMonthlyRevenue
    @Year INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MONTH(o.OrderDate) AS [Month],
           SUM(oi.LineTotal) AS Revenue
    FROM dbo.Orders o
    JOIN dbo.OrderItems oi ON oi.OrderID = o.OrderID
    WHERE YEAR(o.OrderDate) = @Year
    GROUP BY MONTH(o.OrderDate)
    ORDER BY [Month];
END
GO


-- Clustered PK indexes created automatically. Add these nonclustered indexes:
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate ON dbo.Orders(OrderDate);
CREATE NONCLUSTERED INDEX IX_OrderItems_ProductID ON dbo.OrderItems(ProductID) INCLUDE (OrderID, LineTotal);
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID ON dbo.Orders(CustomerID) INCLUDE (OrderDate, TotalAmount);
CREATE NONCLUSTERED INDEX IX_Products_CategoryID ON dbo.Products(CategoryID);
GO

-- Update statistics (after bulk loads)
EXEC sp_updatestats;



-- Transactions, concurrency & an example order insertion pattern
BEGIN TRY
    BEGIN TRAN;

    DECLARE @CustomerID INT = 1;
    DECLARE @Ship NVARCHAR(400) = 'Some Addr';
    DECLARE @Bill NVARCHAR(400) = 'Some Addr';
    DECLARE @ShippingCost DECIMAL(10,2) = 40;
    DECLARE @Discount DECIMAL(10,2) = 0;

    INSERT INTO dbo.Orders (CustomerID, ShippingAddress, BillingAddress, ShippingCost, Discount)
    VALUES (@CustomerID, @Ship, @Bill, @ShippingCost, @Discount);

    DECLARE @OrderID INT = SCOPE_IDENTITY();

    -- insert items (example)
    INSERT INTO dbo.OrderItems (OrderID, ProductID, Quantity, UnitPrice)
    VALUES (@OrderID, 1, 1, 599.00);

    -- update stock
    UPDATE dbo.Products
    SET StockQty = StockQty - 1
    WHERE ProductID = 1;

    -- recalc total
    UPDATE dbo.Orders
    SET TotalAmount = (SELECT SUM(LineTotal) FROM dbo.OrderItems WHERE OrderID = @OrderID) + ShippingCost - Discount
    WHERE OrderID = @OrderID;

    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRAN;
    THROW;
END CATCH;



-- Manual backup example:

BACKUP DATABASE ECommerceDB TO DISK = 'C:\Backups\ECommerceDB_Full.bak' WITH INIT;

