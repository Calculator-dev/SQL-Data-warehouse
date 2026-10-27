/*
===============================================================================
Date Range Exploration
===============================================================================
Purpose:
    - To determine the temporal boundaries of key data points.
    - To understand the range of historical data.

SQL Functions Used:
    - MIN(), MAX(), EXTRACT()
===============================================================================
*/

-- Determine the first and last order date and the total duration in months
-- (PostgreSQL has no DATEDIFF; the month difference is calculated from the
-- year and month parts, which matches SQL Server's DATEDIFF(MONTH, ...))
SELECT
    MIN(order_date) AS first_order_date,
    MAX(order_date) AS last_order_date,
    (EXTRACT(YEAR FROM MAX(order_date)) - EXTRACT(YEAR FROM MIN(order_date))) * 12
      + (EXTRACT(MONTH FROM MAX(order_date)) - EXTRACT(MONTH FROM MIN(order_date))) AS order_range_months
FROM gold.fact_sales;

-- Find the youngest and oldest customer based on birthdate
-- (Matches SQL Server's DATEDIFF(YEAR, ...), which compares only the years)
SELECT
    MIN(birthdate)                                                       AS oldest_birthdate,
    EXTRACT(YEAR FROM CURRENT_DATE) - EXTRACT(YEAR FROM MIN(birthdate)) AS oldest_age,
    MAX(birthdate)                                                       AS youngest_birthdate,
    EXTRACT(YEAR FROM CURRENT_DATE) - EXTRACT(YEAR FROM MAX(birthdate)) AS youngest_age
FROM gold.dim_customers;
