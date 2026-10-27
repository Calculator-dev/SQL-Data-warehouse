/*
=============================================================
Create Database and Schemas (PostgreSQL)
=============================================================
Script Purpose:
    This script creates a new database named 'datawarehouseanalytics'.
    If the database exists, it is dropped and recreated. Additionally,
    this script creates a schema called gold and loads the gold tables
    from CSV files.

WARNING:
    Running this script will drop the entire 'datawarehouseanalytics'
    database if it exists. All data in the database will be permanently
    deleted. Proceed with caution and ensure you have proper backups
    before running this script.

How to run in pgAdmin:
    PostgreSQL has no USE statement, so the script runs in two steps.

    Step 1: Open the Query Tool on the 'postgres' database and run the
            STEP 1 statements.
    Step 2: Refresh 'Databases', open a new Query Tool on the
            'datawarehouseanalytics' database and run the STEP 2 statements.

Note:
    The COPY paths point to
    '/Users/calculator/Downloads/sql-data-analytics-project/01_datasets/csv-files/'.
    Change them to the folder where you saved the CSV files.
=============================================================
*/

-- =============================================================
-- STEP 1: Run while connected to the 'postgres' database
-- =============================================================

-- Drop and recreate the 'datawarehouseanalytics' database
-- (FORCE disconnects other sessions; requires PostgreSQL 13+)
DROP DATABASE IF EXISTS datawarehouseanalytics WITH (FORCE);

CREATE DATABASE datawarehouseanalytics;

-- =============================================================
-- STEP 2: Run while connected to the 'datawarehouseanalytics' database
-- =============================================================

-- Create Schemas

CREATE SCHEMA IF NOT EXISTS gold;

CREATE TABLE gold.dim_customers (
    customer_key     INT,
    customer_id      INT,
    customer_number  VARCHAR(50),
    first_name       VARCHAR(50),
    last_name        VARCHAR(50),
    country          VARCHAR(50),
    marital_status   VARCHAR(50),
    gender           VARCHAR(50),
    birthdate        DATE,
    create_date      DATE
);

CREATE TABLE gold.dim_products (
    product_key      INT,
    product_id       INT,
    product_number   VARCHAR(50),
    product_name     VARCHAR(50),
    category_id      VARCHAR(50),
    category         VARCHAR(50),
    subcategory      VARCHAR(50),
    maintenance      VARCHAR(50),
    cost             INT,
    product_line     VARCHAR(50),
    start_date       DATE
);

CREATE TABLE gold.fact_sales (
    order_number     VARCHAR(50),
    product_key      INT,
    customer_key     INT,
    order_date       DATE,
    shipping_date    DATE,
    due_date         DATE,
    sales_amount     INT,
    quantity         SMALLINT,
    price            INT
);

TRUNCATE TABLE gold.dim_customers;
COPY gold.dim_customers
FROM '/Users/calculator/Downloads/sql-data-analytics-project/01_datasets/csv-files/gold.dim_customers.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ',');

TRUNCATE TABLE gold.dim_products;
COPY gold.dim_products
FROM '/Users/calculator/Downloads/sql-data-analytics-project/01_datasets/csv-files/gold.dim_products.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ',');

TRUNCATE TABLE gold.fact_sales;
COPY gold.fact_sales
FROM '/Users/calculator/Downloads/sql-data-analytics-project/01_datasets/csv-files/gold.fact_sales.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ',');
