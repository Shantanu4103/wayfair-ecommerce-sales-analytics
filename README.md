# E-commerce Sales Analysis: MySQL + Power BI

An end-to-end analytics project: raw CSV files → cleaned MySQL database → SQL analysis → an interactive Power BI dashboard.

> **Author:** Shantanu Shrotri · **Contact:** shantanu.shrotri@gmail.com / https://www.linkedin.com/in/shantanu-shrotri/


---

## Business questions

1. How is revenue and profit trending, and what drives the seasonal peak?
2. Which products and categories earn the most, and which have a returns problem?
3. Which acquisition channels bring customers who actually buy and come back?
4. Are discount codes paying for themselves?

## Dataset

Four CSV files from Kaggle describing two years of online home-goods orders (1 Jan 2024 – 31 Dec 2025).

| Table | Rows | Description |
|---|---|---|
| `customers` | 3,600 | Signup date, state, acquisition channel |
| `products` | 90 | Name, category, list price, unit cost |
| `orders` | 9,207 (after de-duplication) | Date, status, payment method, discount code, shipping fee |
| `order_items` | 15,608 | Quantity, unit price, discount per order line |

## Tools

MySQL 8 (command line) · SQL (CTEs, window functions, views) · Power BI Desktop · DAX

## Repository contents

| File | Purpose |
|---|---|
| `import_data.sql` | Creates the tables and loads the CSV files |
| `analysis.sql` | Data-quality checks, KPIs, trends, product, customer and promotion analysis, plus the views Power BI reads |
| `dax_measures.md` | Every DAX measure and calculated table used in the report |
| `ecommerce_dashboard.pbix` | The Power BI report |
| `dashboard.pdf` | Dashboard exported to PDF |
| `screenshots/` | One image per dashboard page |

## Data cleaning

| Issue found | What I did |
|---|---|
| 38 exact duplicate rows in `orders.csv` | Skipped on import (`IGNORE`), leaving 9,207 unique orders |
| Dates stored as DD-MM-YYYY | Converted with `STR_TO_DATE` |
| Product categories in 24 spelling and spacing variants (e.g. `Kitchen`, `kitchen`, ` KITCHEN `) | Trimmed and standardized to 8 categories |
| 199 order lines with a blank `unit_price` | Filled from the product list price. Prices rose exactly 5% on 1 Jan 2025, so 2025 lines use list price × 1.05 |
| Empty discount codes | Stored as `NULL` |
| Windows line endings (`\r\n`) in three of the four files | Handled in the import so no hidden characters end up in the data |

## Method

- **Revenue definition:** `quantity × unit_price − discount_amount`, counting only `completed` orders. Returned and canceled orders are analysed separately.
- **Clean layer:** SQL views (`v_order_lines`, `v_orders`) apply these rules once, so every query and the dashboard use identical definitions.
- **Customer analysis:** RFM segmentation with `NTILE`, cohort retention, repeat-purchase rate and channel conversion.
- **Dashboard:** star-schema model in Power BI (a date table plus fact and dimension views), with DAX measures for year-over-year growth, margins, return rates and retention.

## Key findings

1. **Scale and profitability.** Completed sales total **$1.88M** from 8,456 orders. The average order is **$222.56** and gross margin is **49.2%**.
2. **Growth.** 2025 revenue grew **21%** over 2024 ($0.85M → $1.03M). Part of this comes from the 5% price increase on 1 Jan 2025.
3. **Seasonality and discounting.** November and December are the peak months, but discounts rise from under 2.5% of sales in most months to **6.4–7.6%** in Nov–Dec.
4. **Holiday promo trade-off.** `HOLIDAY20` accounts for about two-thirds of all discounts ($30.4K of $45.3K). Its orders average **$169 vs $230** without a code, and margin is **38% vs 50.4%**.
5. **Furniture returns.** Furniture is the largest category (about $323K) but is returned **12.1%** of the time, against roughly 4–5% elsewhere.
6. **Channel quality.** Paid social brings 831 signups but only **44%** become buyers, earning **$287 per signup**. Referral converts **68%** and earns **$747 per signup**; organic search earns $629.
7. **Customer base.** About 43% of signups have never completed a purchase, and 36% of buyers ordered only once. The top ~17% of buyers ("Champions") generate about **36% of revenue**, while "At Risk" customers represent about **$624K** of past revenue to win back.
8. **Catalogue.** 51 of 90 products generate 80% of revenue.

## Recommendations

- Review the Furniture return rate (product quality, descriptions, sizing and packaging) before scaling the category.
- Shift acquisition budget from paid social toward referral and organic channels, or fix the paid-social onboarding experience.
- Test a smaller or targeted holiday discount, since `HOLIDAY20` lowers both basket size and margin.
- Run a win-back campaign for "At Risk" customers.

## How to reproduce

1. Create an empty database, then connect:
   `mysql --local-infile=1 -u root -p your_database_name`
2. Edit the four file paths in `import_data.sql`, then run `source import_data.sql;`
3. Run `source analysis.sql;`
4. Open the `.pbix` in Power BI Desktop. Install MySQL Connector/NET first, then point the data source at your own server and database.

## Limitations

- The data covers only two years, so customer lifetime value is understated for recent signups.
- Several customers placed 49–75 orders each (about 20× the average buyer), which may indicate resellers, business accounts or test records, and they were left in the data.
- The data does not separate the effect of the holiday promo from normal holiday demand, so the promo's causal impact on sales cannot be measured here.
- RFM segment sizes can shift by a few customers between runs because tied customers are bucketed differently.
