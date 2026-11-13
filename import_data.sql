/* =====================================================================
   IMPORT SCRIPT - creates the 4 tables and loads the CSV files
   ---------------------------------------------------------------------
   BEFORE RUNNING:
   1. Replace /path/to/folder/ in the four LOAD DATA lines with the folder
      that holds your CSV files (use forward slashes on Windows, e.g.
      C:/Users/yourname/Downloads/).
   2. Connect with local file loading enabled:
         mysql --local-infile=1 -u root -p your_database_name
      If MySQL says loading local data is disabled, run once:
         SET GLOBAL local_infile = 1;
   NOTE ON LINE ENDINGS:
   customers.csv, products.csv and orders.csv use Windows line endings
   (\r\n); order_items.csv uses \n. That is why the LINES TERMINATED BY
   value differs between the files below.
   ===================================================================== */

DROP TABLE IF EXISTS order_items, orders, products, customers;

-- 1. CUSTOMERS
CREATE TABLE customers (
    customer_id          INT PRIMARY KEY,
    signup_date          DATE,
    state                CHAR(2),
    acquisition_channel  VARCHAR(30)
);

LOAD DATA LOCAL INFILE '/path/to/folder/customers.csv'
INTO TABLE customers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(customer_id, @signup_date, state, acquisition_channel)
SET signup_date = STR_TO_DATE(@signup_date, '%d-%m-%Y');

-- 2. PRODUCTS
CREATE TABLE products (
    product_id    INT PRIMARY KEY,
    product_name  VARCHAR(100),
    category      VARCHAR(30),
    list_price    DECIMAL(10,2),
    unit_cost     DECIMAL(10,2)
);

LOAD DATA LOCAL INFILE '/path/to/folder/products.csv'
INTO TABLE products
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(product_id, product_name, @category, list_price, unit_cost)
SET category = CONCAT(UPPER(LEFT(TRIM(@category), 1)), LOWER(SUBSTRING(TRIM(@category), 2)));

-- 3. ORDERS  (IGNORE skips the 38 exact duplicate rows in the CSV)
CREATE TABLE orders (
    order_id        INT PRIMARY KEY,
    customer_id     INT,
    order_date      DATE,
    status          VARCHAR(20),
    payment_method  VARCHAR(20),
    discount_code   VARCHAR(20),
    shipping_fee    DECIMAL(6,2),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

LOAD DATA LOCAL INFILE '/path/to/folder/orders.csv'
IGNORE INTO TABLE orders
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(order_id, customer_id, @order_date, status, payment_method, @discount_code, shipping_fee)
SET order_date    = STR_TO_DATE(@order_date, '%d-%m-%Y'),
    discount_code = NULLIF(@discount_code, '');

-- 4. ORDER_ITEMS  (blank unit_price values are stored as NULL)
CREATE TABLE order_items (
    order_id         INT,
    product_id       INT,
    quantity         INT,
    unit_price       DECIMAL(10,2),
    discount_amount  DECIMAL(10,2),
    PRIMARY KEY (order_id, product_id),
    FOREIGN KEY (order_id)   REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

LOAD DATA LOCAL INFILE '/path/to/folder/order_items.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, product_id, quantity, @unit_price, discount_amount)
SET unit_price = NULLIF(@unit_price, '');

-- Verify: expect 3600 / 90 / 9207 / 15608
SELECT 'customers'   AS tbl, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'products',    COUNT(*) FROM products
UNION ALL SELECT 'orders',      COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items;
