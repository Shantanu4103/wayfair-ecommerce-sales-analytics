# DAX Measures and Calculated Tables

All measures used in the Power BI report. Revenue measures count only `completed` orders.

## Model

| Table | Type | Relationship |
|---|---|---|
| `pbi_fact_orders` | Fact (one row per order) | `order_date` → `Date[Date]`, `customer_id` → `pbi_dim_customers` |
| `pbi_fact_order_lines` | Fact (one row per order line) | `order_date` → `Date[Date]`, `product_id` → `pbi_dim_products` |
| `pbi_dim_customers` | Dimension | |
| `pbi_dim_products` | Dimension | |
| `Date` | Calculated date table (marked as date table) | |
| `pbi_cohort` | Stand-alone (no relationships) | |
| `Waterfall Steps` | Stand-alone helper table | |

## Date table

```DAX
Date = CALENDARAUTO()
```
```DAX
Year = YEAR('Date'[Date])
```
```DAX
Month No = MONTH('Date'[Date])
```
```DAX
Month = FORMAT('Date'[Date], "MMM")
```
```DAX
Year Month = FORMAT('Date'[Date], "yyyy-MM")
```

## Core KPIs (on `pbi_fact_orders`)

```DAX
Net Revenue = CALCULATE(SUM(pbi_fact_orders[net_revenue]), pbi_fact_orders[status] = "completed")
```
```DAX
Gross Profit = CALCULATE(SUM(pbi_fact_orders[gross_profit]), pbi_fact_orders[status] = "completed")
```
```DAX
Margin % = DIVIDE([Gross Profit], [Net Revenue])
```
```DAX
Orders = CALCULATE(DISTINCTCOUNT(pbi_fact_orders[order_id]), pbi_fact_orders[status] = "completed")
```
```DAX
AOV = DIVIDE([Net Revenue], [Orders])
```
```DAX
All Orders = COUNTROWS(pbi_fact_orders)
```
```DAX
Return Rate = DIVIDE(
    CALCULATE(COUNTROWS(pbi_fact_orders), pbi_fact_orders[status] = "returned"),
    CALCULATE(COUNTROWS(pbi_fact_orders), pbi_fact_orders[status] <> "canceled"))
```
```DAX
Cancel Rate = DIVIDE(
    CALCULATE(COUNTROWS(pbi_fact_orders), pbi_fact_orders[status] = "canceled"),
    COUNTROWS(pbi_fact_orders))
```
```DAX
Returned Value = CALCULATE(SUM(pbi_fact_orders[net_revenue]), pbi_fact_orders[status] = "returned")
```

## Time intelligence

```DAX
Revenue LY = CALCULATE([Net Revenue], SAMEPERIODLASTYEAR('Date'[Date]))
```
```DAX
YoY % = DIVIDE([Net Revenue] - [Revenue LY], [Revenue LY])
```
```DAX
YoY Variance = [Net Revenue] - [Revenue LY]
```
```DAX
Revenue YTD = TOTALYTD([Net Revenue], 'Date'[Date])
```
```DAX
Revenue Prev Month = CALCULATE([Net Revenue], DATEADD('Date'[Date], -1, MONTH))
```
```DAX
MoM % = DIVIDE([Net Revenue] - [Revenue Prev Month], [Revenue Prev Month])
```
```DAX
Revenue Rolling 3M = CALCULATE([Net Revenue], DATESINPERIOD('Date'[Date], MAX('Date'[Date]), -3, MONTH))
```
```DAX
YoY Color = IF([YoY %] >= 0, "#2E7D32", "#C62828")
```
`YoY Color` drives conditional formatting (green for growth, red for decline).

## Discounts and margin waterfall

```DAX
Gross Revenue = CALCULATE(SUM(pbi_fact_orders[gross_revenue]), pbi_fact_orders[status] = "completed")
```
```DAX
Total Discounts = CALCULATE(SUM(pbi_fact_orders[discount_amount]), pbi_fact_orders[status] = "completed")
```
```DAX
Total COGS = CALCULATE(SUM(pbi_fact_orders[cogs]), pbi_fact_orders[status] = "completed")
```
```DAX
Discount % = DIVIDE([Total Discounts], [Gross Revenue])
```
```DAX
Waterfall Steps = DATATABLE("Step", STRING, "Sort", INTEGER,
    {{"Gross Revenue", 1}, {"Discounts", 2}, {"COGS", 3}})
```
```DAX
Waterfall Value = SWITCH(SELECTEDVALUE('Waterfall Steps'[Step]),
    "Gross Revenue", [Gross Revenue],
    "Discounts", -[Total Discounts],
    "COGS", -[Total COGS])
```

## Products (on `pbi_fact_order_lines`)

```DAX
Product Revenue = CALCULATE(SUM(pbi_fact_order_lines[net_revenue]), pbi_fact_order_lines[status] = "completed")
```
```DAX
Product Profit = CALCULATE(SUM(pbi_fact_order_lines[gross_profit]), pbi_fact_order_lines[status] = "completed")
```
```DAX
Product Margin % = DIVIDE([Product Profit], [Product Revenue])
```
```DAX
Units Sold = CALCULATE(SUM(pbi_fact_order_lines[quantity]), pbi_fact_order_lines[status] = "completed")
```
```DAX
Line Return Rate = DIVIDE(
    CALCULATE(COUNTROWS(pbi_fact_order_lines), pbi_fact_order_lines[status] = "returned"),
    CALCULATE(COUNTROWS(pbi_fact_order_lines), pbi_fact_order_lines[status] <> "canceled"))
```

## Customers (on `pbi_dim_customers`)

```DAX
Total Signups = COUNTROWS(pbi_dim_customers)
```
```DAX
Buying Customers = CALCULATE(DISTINCTCOUNT(pbi_fact_orders[customer_id]), pbi_fact_orders[status] = "completed")
```
```DAX
Lifetime Conversion % = DIVIDE(
    CALCULATE([Buying Customers], REMOVEFILTERS('Date')),
    [Total Signups])
```
```DAX
Revenue per Signup = DIVIDE(
    CALCULATE([Net Revenue], REMOVEFILTERS('Date')),
    [Total Signups])
```
```DAX
Repeat Rate = DIVIDE(
    COUNTROWS(FILTER(pbi_dim_customers, pbi_dim_customers[lifetime_orders] >= 2)),
    COUNTROWS(FILTER(pbi_dim_customers, pbi_dim_customers[lifetime_orders] >= 1)))
```
```DAX
Revenue per Buyer = DIVIDE([Net Revenue], [Buying Customers])
```

## Cohort retention (on `pbi_cohort`)

```DAX
Cohort Retention % = DIVIDE(AVERAGE(pbi_cohort[retention_pct]), 100)
```

## Modelling notes

- `REMOVEFILTERS('Date')` keeps conversion and revenue-per-signup as lifetime figures, because signups are not tied to the Year slicer.
- Measures are placed on the fact table they read from. Using a measure from one fact table to split by a field of the other returns the grand total on every row, because the two fact tables are not related to each other.
- The measure is named `Total COGS` rather than `COGS` because the `cogs` column already exists in `pbi_fact_orders`, and DAX names are not case-sensitive.
