/* =====================================================================
   E-COMMERCE ANALYSIS  (MySQL 8.0+)
   Tables: customers, products, orders, order_items
   Run in the mysql command line:
       mysql -u root -p your_database_name
       mysql> source /path/to/analysis.sql;
   Part 0 repairs a line-ending issue, Part A creates the clean views (run once).
   Parts B-H are analysis queries (run one at a time, or all at once).
   Part I creates the views that Power BI will connect to.
   ===================================================================== */


/* =====================================================================
   PART 0 - ONE-TIME REPAIR (safe to run more than once)
   customers.csv, products.csv and orders.csv use Windows line endings
   (\r\n). If they were imported with LINES TERMINATED BY '\n', a hidden
   carriage return stays on the end of the last column of each row.
   This removes it. (order_items.csv uses plain \n, so it is fine.)
   ===================================================================== */
UPDATE customers SET acquisition_channel = TRIM(TRAILING '\r' FROM acquisition_channel)
WHERE acquisition_channel LIKE CONCAT('%', CHAR(13));


/* =====================================================================
   PART A - CLEAN LAYER (views)
   Business rules used everywhere below:
   * Net revenue  = quantity * unit_price - discount_amount
   * Only status = 'completed' counts as real revenue.
     'returned' and 'canceled' orders are analysed separately.
   * 199 order lines have a blank unit_price. Prices went up exactly 5%
     on 2025-01-01, so blanks are filled with list_price (x1.05 for 2025).
   ===================================================================== */

CREATE OR REPLACE VIEW v_order_lines AS
SELECT
    o.order_id,
    o.order_date,
    DATE_SUB(o.order_date, INTERVAL DAYOFMONTH(o.order_date) - 1 DAY) AS order_month,
    o.customer_id,
    o.status,
    o.payment_method,
    o.discount_code,
    oi.product_id,
    p.product_name,
    p.category,
    oi.quantity,
    COALESCE(
        oi.unit_price,
        ROUND(p.list_price * CASE WHEN o.order_date >= '2025-01-01' THEN 1.05 ELSE 1 END, 2)
    )                                                        AS unit_price,
    (oi.unit_price IS NULL)                                  AS price_was_filled,
    oi.discount_amount,
    oi.quantity * COALESCE(
        oi.unit_price,
        ROUND(p.list_price * CASE WHEN o.order_date >= '2025-01-01' THEN 1.05 ELSE 1 END, 2)
    )                                                        AS gross_revenue,
    oi.quantity * COALESCE(
        oi.unit_price,
        ROUND(p.list_price * CASE WHEN o.order_date >= '2025-01-01' THEN 1.05 ELSE 1 END, 2)
    ) - oi.discount_amount                                   AS net_revenue,
    oi.quantity * p.unit_cost                                AS cogs
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id
JOIN products p ON p.product_id = oi.product_id;


CREATE OR REPLACE VIEW v_orders AS
SELECT
    l.order_id,
    l.order_date,
    l.order_month,
    l.customer_id,
    l.status,
    l.payment_method,
    l.discount_code,
    o.shipping_fee,
    COUNT(*)                                   AS line_count,
    SUM(l.quantity)                            AS units,
    SUM(l.gross_revenue)                       AS gross_revenue,
    SUM(l.discount_amount)                     AS discount_amount,
    SUM(l.net_revenue)                         AS net_revenue,
    SUM(l.cogs)                                AS cogs,
    SUM(l.net_revenue) - SUM(l.cogs)           AS gross_profit
FROM v_order_lines l
JOIN orders o ON o.order_id = l.order_id
GROUP BY l.order_id, l.order_date, l.order_month, l.customer_id, l.status,
         l.payment_method, l.discount_code, o.shipping_fee;


/* =====================================================================
   PART B - DATA QUALITY CHECKS
   ===================================================================== */

-- B1. Row counts
SELECT 'customers' AS tbl, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'products',    COUNT(*) FROM products
UNION ALL SELECT 'orders',      COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items;

-- B2. Date coverage
SELECT MIN(order_date) AS first_order, MAX(order_date) AS last_order,
       DATEDIFF(MAX(order_date), MIN(order_date)) + 1 AS days_covered
FROM orders;

-- B3. How many lines had a missing price and were filled
SELECT SUM(price_was_filled) AS filled_lines, COUNT(*) AS total_lines,
       ROUND(100 * SUM(price_was_filled) / COUNT(*), 2) AS pct_filled
FROM v_order_lines;

-- B4. Customers who signed up but never ordered
SELECT COUNT(*) AS never_ordered,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM customers), 1) AS pct_of_customers
FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id);

-- B5. Orders placed BEFORE the customer's signup date (should be 0)
SELECT COUNT(*) AS orders_before_signup
FROM orders o JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_date < c.signup_date;


/* =====================================================================
   PART C - HEADLINE KPIs
   ===================================================================== */

-- C1. Overall KPIs (completed orders only)
SELECT
    COUNT(*)                                       AS orders,
    COUNT(DISTINCT customer_id)                    AS buying_customers,
    ROUND(SUM(net_revenue), 2)                     AS net_revenue,
    ROUND(SUM(gross_profit), 2)                    AS gross_profit,
    ROUND(100 * SUM(gross_profit) / SUM(net_revenue), 1) AS gross_margin_pct,
    ROUND(AVG(net_revenue), 2)                     AS avg_order_value,
    ROUND(SUM(units) / COUNT(*), 2)                AS units_per_order,
    ROUND(SUM(shipping_fee), 2)                    AS shipping_fees_collected
FROM v_orders
WHERE status = 'completed';

-- C2. Order status mix (completed / returned / canceled) with revenue at stake
SELECT status,
       COUNT(*)                                               AS orders,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)       AS pct_of_orders,
       ROUND(SUM(net_revenue), 2)                             AS revenue_value
FROM v_orders
GROUP BY status
ORDER BY orders DESC;

-- C3. Year-over-year comparison
SELECT YEAR(order_date)                         AS yr,
       COUNT(*)                                 AS orders,
       COUNT(DISTINCT customer_id)              AS customers,
       ROUND(SUM(net_revenue), 2)               AS net_revenue,
       ROUND(AVG(net_revenue), 2)               AS avg_order_value,
       ROUND(100 * SUM(gross_profit) / SUM(net_revenue), 1) AS margin_pct
FROM v_orders
WHERE status = 'completed'
GROUP BY YEAR(order_date)
ORDER BY yr;


/* =====================================================================
   PART D - TRENDS OVER TIME
   ===================================================================== */

-- D1. Monthly revenue with month-over-month and year-over-year growth
WITH monthly AS (
    SELECT order_month,
           COUNT(*)                   AS orders,
           SUM(net_revenue)           AS revenue,
           SUM(gross_profit)          AS profit
    FROM v_orders
    WHERE status = 'completed'
    GROUP BY order_month
)
SELECT order_month,
       orders,
       ROUND(revenue, 2) AS revenue,
       ROUND(profit, 2)  AS profit,
       ROUND(100 * (revenue - LAG(revenue, 1)  OVER (ORDER BY order_month))
                 / LAG(revenue, 1)  OVER (ORDER BY order_month), 1) AS mom_growth_pct,
       ROUND(100 * (revenue - LAG(revenue, 12) OVER (ORDER BY order_month))
                 / LAG(revenue, 12) OVER (ORDER BY order_month), 1) AS yoy_growth_pct
FROM monthly
ORDER BY order_month;

-- D2. Seasonality: average revenue by calendar month (are Nov/Dec spikes real?)
SELECT MONTH(order_month) AS month_no,
       MONTHNAME(order_month) AS month_name,
       ROUND(AVG(revenue), 2) AS avg_monthly_revenue
FROM (
    SELECT order_month, SUM(net_revenue) AS revenue
    FROM v_orders WHERE status = 'completed'
    GROUP BY order_month
) m
GROUP BY MONTH(order_month), MONTHNAME(order_month)
ORDER BY month_no;

-- D3. Day-of-week pattern
SELECT DAYOFWEEK(order_date) AS dow_no,
       DAYNAME(order_date)   AS day_name,
       COUNT(*)              AS orders,
       ROUND(SUM(net_revenue), 2) AS revenue
FROM v_orders
WHERE status = 'completed'
GROUP BY DAYOFWEEK(order_date), DAYNAME(order_date)
ORDER BY dow_no;


/* =====================================================================
   PART E - PRODUCTS & CATEGORIES
   ===================================================================== */

-- E1. Category performance
SELECT category,
       SUM(quantity)                                   AS units,
       ROUND(SUM(net_revenue), 2)                      AS revenue,
       ROUND(SUM(net_revenue - cogs), 2)               AS profit,
       ROUND(100 * SUM(net_revenue - cogs) / SUM(net_revenue), 1) AS margin_pct,
       ROUND(100 * SUM(net_revenue) / SUM(SUM(net_revenue)) OVER (), 1) AS revenue_share_pct
FROM v_order_lines
WHERE status = 'completed'
GROUP BY category
ORDER BY revenue DESC;

-- E2. Top 10 products by profit
SELECT product_id, product_name, category,
       SUM(quantity)                     AS units,
       ROUND(SUM(net_revenue), 2)        AS revenue,
       ROUND(SUM(net_revenue - cogs), 2) AS profit
FROM v_order_lines
WHERE status = 'completed'
GROUP BY product_id, product_name, category
ORDER BY profit DESC
LIMIT 10;

-- E3. Bottom 10 products by profit (candidates to drop or reprice)
SELECT product_id, product_name, category,
       SUM(quantity)                     AS units,
       ROUND(SUM(net_revenue), 2)        AS revenue,
       ROUND(SUM(net_revenue - cogs), 2) AS profit
FROM v_order_lines
WHERE status = 'completed'
GROUP BY product_id, product_name, category
ORDER BY profit ASC
LIMIT 10;

-- E4. Pareto: how many products produce 80% of revenue?
WITH p AS (
    SELECT product_id, product_name, SUM(net_revenue) AS revenue
    FROM v_order_lines WHERE status = 'completed'
    GROUP BY product_id, product_name
),
ranked AS (
    SELECT *,
           SUM(revenue) OVER (ORDER BY revenue DESC)  AS running_rev,
           SUM(revenue) OVER ()                       AS total_rev,
           ROW_NUMBER() OVER (ORDER BY revenue DESC)  AS rnk
    FROM p
)
SELECT rnk, product_name, ROUND(revenue, 2) AS revenue,
       ROUND(100 * running_rev / total_rev, 1) AS cumulative_pct
FROM ranked
ORDER BY rnk;
-- (find the row where cumulative_pct first passes 80)

-- E5. Return rate by category (returned orders / all non-canceled orders)
SELECT category,
       SUM(CASE WHEN status = 'returned'  THEN 1 ELSE 0 END)           AS returned_lines,
       SUM(CASE WHEN status <> 'canceled' THEN 1 ELSE 0 END)           AS shipped_lines,
       ROUND(100 * SUM(CASE WHEN status = 'returned' THEN 1 ELSE 0 END)
                 / SUM(CASE WHEN status <> 'canceled' THEN 1 ELSE 0 END), 2) AS return_rate_pct
FROM v_order_lines
GROUP BY category
ORDER BY return_rate_pct DESC;

-- E6. Market basket: top 10 product pairs bought together
SELECT p1.product_name AS product_a,
       p2.product_name AS product_b,
       COUNT(*)        AS times_together
FROM order_items a
JOIN order_items b ON a.order_id = b.order_id AND a.product_id < b.product_id
JOIN products p1   ON p1.product_id = a.product_id
JOIN products p2   ON p2.product_id = b.product_id
GROUP BY p1.product_name, p2.product_name
ORDER BY times_together DESC
LIMIT 10;


/* =====================================================================
   PART F - CUSTOMERS
   ===================================================================== */

-- F1. Acquisition channel: signups, conversion to buyer, revenue, revenue per signup
SELECT c.acquisition_channel,
       COUNT(DISTINCT c.customer_id)                          AS signups,
       COUNT(DISTINCT o.customer_id)                          AS buyers,
       ROUND(100 * COUNT(DISTINCT o.customer_id)
                 / COUNT(DISTINCT c.customer_id), 1)          AS conversion_pct,
       ROUND(COALESCE(SUM(o.net_revenue), 0), 2)              AS revenue,
       ROUND(COALESCE(SUM(o.net_revenue), 0)
             / COUNT(DISTINCT c.customer_id), 2)              AS revenue_per_signup
FROM customers c
LEFT JOIN v_orders o ON o.customer_id = c.customer_id AND o.status = 'completed'
GROUP BY c.acquisition_channel
ORDER BY revenue DESC;

-- F2. Revenue by state (top 15)
SELECT c.state,
       COUNT(DISTINCT o.customer_id) AS buyers,
       COUNT(*)                      AS orders,
       ROUND(SUM(o.net_revenue), 2)  AS revenue
FROM v_orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.status = 'completed'
GROUP BY c.state
ORDER BY revenue DESC
LIMIT 15;

-- F3. Repeat-purchase rate: how many buyers ordered once vs 2+ times
WITH per_cust AS (
    SELECT customer_id, COUNT(*) AS orders
    FROM v_orders WHERE status = 'completed'
    GROUP BY customer_id
)
SELECT CASE WHEN orders = 1 THEN '1 order'
            WHEN orders = 2 THEN '2 orders'
            WHEN orders BETWEEN 3 AND 4 THEN '3-4 orders'
            ELSE '5+ orders' END           AS segment,
       COUNT(*)                            AS customers,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_customers
FROM per_cust
GROUP BY segment
ORDER BY MIN(orders);

-- F4. Customer lifetime value: top 20 customers
SELECT customer_id,
       COUNT(*)                     AS orders,
       ROUND(SUM(net_revenue), 2)   AS lifetime_revenue,
       MIN(order_date)              AS first_order,
       MAX(order_date)              AS last_order
FROM v_orders
WHERE status = 'completed'
GROUP BY customer_id
ORDER BY lifetime_revenue DESC
LIMIT 20;

-- F5. RFM segmentation (Recency, Frequency, Monetary) -> named segments
CREATE OR REPLACE VIEW v_rfm AS
WITH base AS (
    SELECT customer_id,
           DATEDIFF((SELECT MAX(order_date) FROM orders), MAX(order_date)) AS recency_days,
           COUNT(*)                                                       AS frequency,
           SUM(net_revenue)                                               AS monetary
    FROM v_orders
    WHERE status = 'completed'
    GROUP BY customer_id
),
scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,   -- 5 = most recent
           NTILE(5) OVER (ORDER BY frequency)         AS f_score,
           NTILE(5) OVER (ORDER BY monetary)          AS m_score
    FROM base
)
SELECT customer_id, recency_days, frequency, ROUND(monetary, 2) AS monetary,
       r_score, f_score, m_score,
       CASE
           WHEN r_score >= 4 AND f_score >= 4                 THEN 'Champions'
           WHEN r_score >= 3 AND f_score >= 3                 THEN 'Loyal'
           WHEN r_score >= 4 AND f_score <= 2                 THEN 'New / Promising'
           WHEN r_score <= 2 AND f_score >= 3                 THEN 'At Risk'
           WHEN r_score <= 2 AND f_score <= 2                 THEN 'Lost / Hibernating'
           ELSE 'Needs Attention'
       END AS segment
FROM scored;

SELECT segment,
       COUNT(*)                  AS customers,
       ROUND(SUM(monetary), 2)   AS revenue,
       ROUND(AVG(monetary), 2)   AS avg_revenue_per_customer
FROM v_rfm
GROUP BY segment
ORDER BY revenue DESC;

-- F6. Cohort retention: customers grouped by month of first order,
--     % still ordering N months later (months_since_first = 0, 1, 2, ...)
WITH first_order AS (
    SELECT customer_id,
           MIN(order_month) AS cohort_month
    FROM v_orders WHERE status = 'completed'
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT o.customer_id, f.cohort_month,
           PERIOD_DIFF(DATE_FORMAT(o.order_month, '%Y%m'),
                       DATE_FORMAT(f.cohort_month, '%Y%m')) AS months_since_first
    FROM v_orders o
    JOIN first_order f ON f.customer_id = o.customer_id
    WHERE o.status = 'completed'
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS cohort_customers
    FROM first_order GROUP BY cohort_month
)
SELECT a.cohort_month,
       s.cohort_customers,
       a.months_since_first,
       COUNT(*) AS active_customers,
       ROUND(100 * COUNT(*) / s.cohort_customers, 1) AS retention_pct
FROM activity a
JOIN cohort_size s ON s.cohort_month = a.cohort_month
WHERE a.months_since_first <= 12
GROUP BY a.cohort_month, s.cohort_customers, a.months_since_first
ORDER BY a.cohort_month, a.months_since_first;

-- F7. Days between a customer's 1st and 2nd order
WITH ranked AS (
    SELECT customer_id, order_date,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS rn
    FROM v_orders WHERE status = 'completed'
)
SELECT ROUND(AVG(DATEDIFF(r2.order_date, r1.order_date)), 1) AS avg_days_to_second_order,
       COUNT(*)                                               AS customers_with_2nd_order
FROM ranked r1
JOIN ranked r2 ON r1.customer_id = r2.customer_id AND r1.rn = 1 AND r2.rn = 2;


/* =====================================================================
   PART G - DISCOUNTS & PROMOTIONS
   ===================================================================== */

-- G1. Do discount codes help? Compare order value and margin with / without a code
SELECT COALESCE(discount_code, 'No code')            AS promo_code,
       COUNT(*)                                       AS orders,
       ROUND(AVG(gross_revenue), 2)                   AS avg_basket_before_discount,
       ROUND(AVG(net_revenue), 2)                     AS avg_order_value,
       ROUND(SUM(discount_amount), 2)                 AS total_discount_given,
       ROUND(100 * SUM(gross_profit) / SUM(net_revenue), 1) AS margin_pct
FROM v_orders
WHERE status = 'completed'
GROUP BY promo_code
ORDER BY orders DESC;

-- G2. Discount rate by month (are we over-discounting at peak?)
SELECT order_month,
       ROUND(SUM(discount_amount), 2)                         AS discount_given,
       ROUND(100 * SUM(discount_amount) / SUM(gross_revenue), 1) AS discount_pct_of_gross
FROM v_orders
WHERE status = 'completed'
GROUP BY order_month
ORDER BY order_month;

-- G3. Which codes get returned / canceled more often?
SELECT COALESCE(discount_code, 'No code') AS promo_code,
       COUNT(*) AS orders,
       ROUND(100 * SUM(status = 'returned') / COUNT(*), 1) AS return_pct,
       ROUND(100 * SUM(status = 'canceled') / COUNT(*), 1) AS cancel_pct
FROM v_orders
GROUP BY promo_code
ORDER BY orders DESC;


/* =====================================================================
   PART H - PAYMENT & SHIPPING
   ===================================================================== */

-- H1. Payment method mix and value
SELECT payment_method,
       COUNT(*)                                          AS orders,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_orders,
       ROUND(AVG(net_revenue), 2)                        AS avg_order_value,
       ROUND(100 * SUM(status = 'returned') / COUNT(*), 1) AS return_pct
FROM v_orders
GROUP BY payment_method
ORDER BY orders DESC;

-- H2. Free-shipping effect: does a shipping fee change conversion to a completed order?
SELECT CASE WHEN shipping_fee = 0 THEN 'Free shipping' ELSE 'Paid shipping' END AS shipping,
       COUNT(*)                                                       AS orders,
       ROUND(AVG(gross_revenue), 2)                                   AS avg_basket,
       ROUND(MIN(CASE WHEN shipping_fee = 0 THEN gross_revenue END), 2) AS smallest_free_ship_basket,
       ROUND(100 * SUM(status = 'canceled') / COUNT(*), 1)            AS cancel_pct
FROM v_orders
GROUP BY CASE WHEN shipping_fee = 0 THEN 'Free shipping' ELSE 'Paid shipping' END;


/* =====================================================================
   PART I - VIEWS FOR POWER BI
   Connect Power BI to these (plus the customers and products tables).
   ===================================================================== */

-- Fact table 1: one row per order line (use for product / category visuals)
CREATE OR REPLACE VIEW pbi_fact_order_lines AS
SELECT order_id, order_date, customer_id, product_id, category, status,
       payment_method, COALESCE(discount_code, 'No code') AS discount_code,
       quantity, unit_price, gross_revenue, discount_amount, net_revenue, cogs,
       net_revenue - cogs AS gross_profit
FROM v_order_lines;

-- Fact table 2: one row per order (use for orders, AOV, status visuals)
CREATE OR REPLACE VIEW pbi_fact_orders AS
SELECT order_id, order_date, customer_id, status, payment_method,
       COALESCE(discount_code, 'No code') AS discount_code,
       shipping_fee, units, gross_revenue, discount_amount, net_revenue, cogs, gross_profit
FROM v_orders;

-- Customer dimension enriched with RFM segment
CREATE OR REPLACE VIEW pbi_dim_customers AS
SELECT c.customer_id, c.signup_date, c.state, c.acquisition_channel,
       COALESCE(r.segment, 'Never purchased') AS rfm_segment,
       COALESCE(r.frequency, 0)               AS lifetime_orders,
       COALESCE(r.monetary, 0)                AS lifetime_revenue
FROM customers c
LEFT JOIN v_rfm r ON r.customer_id = c.customer_id;

-- Product dimension
CREATE OR REPLACE VIEW pbi_dim_products AS
SELECT product_id, product_name, category, list_price, unit_cost,
       ROUND(100 * (list_price - unit_cost) / list_price, 1) AS list_margin_pct
FROM products;

-- Cohort retention (used by the heatmap on the Customers page).
-- One row per signup cohort (month of first completed order) and months since then.
CREATE OR REPLACE VIEW pbi_cohort AS
WITH first_order AS (
    SELECT customer_id, MIN(order_month) AS cohort_month
    FROM v_orders
    WHERE status = 'completed'
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT o.customer_id, f.cohort_month,
           PERIOD_DIFF(DATE_FORMAT(o.order_month, '%Y%m'),
                       DATE_FORMAT(f.cohort_month, '%Y%m')) AS months_since_first
    FROM v_orders o
    JOIN first_order f ON f.customer_id = o.customer_id
    WHERE o.status = 'completed'
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS cohort_customers
    FROM first_order
    GROUP BY cohort_month
)
SELECT DATE_FORMAT(a.cohort_month, '%Y-%m') AS cohort_label,
       s.cohort_customers,
       a.months_since_first,
       COUNT(*) AS active_customers,
       ROUND(100 * COUNT(*) / s.cohort_customers, 1) AS retention_pct
FROM activity a
JOIN cohort_size s ON s.cohort_month = a.cohort_month
WHERE a.months_since_first BETWEEN 0 AND 12
GROUP BY a.cohort_month, s.cohort_customers, a.months_since_first;
