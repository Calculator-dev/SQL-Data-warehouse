/*
=============================================================
Create Database and Schemas (PostgreSQL)
=============================================================
Script Purpose:
    Creates the 'datawarehouse' database and the three layer
    schemas: bronze, silver and gold.

WARNING:
    Running Step 1 drops the 'datawarehouse' database if it
    already exists. All data in it will be permanently deleted.

How to run in pgAdmin:
    PostgreSQL has no USE statement, so the script runs in two steps.

    Step 1: Open the Query Tool on the 'postgres' database and
            run the STEP 1 statements.
    Step 2: Refresh 'Databases', open a new Query Tool on the
            'datawarehouse' database and run the STEP 2 statements.
=============================================================
*/

-- =============================================================
-- STEP 1: Run while connected to the 'postgres' database
-- =============================================================

-- Drop the database if it exists (FORCE requires PostgreSQL 13+)
DROP DATABASE IF EXISTS datawarehouse WITH (FORCE);

-- Create the database
CREATE DATABASE datawarehouse;

-- =============================================================
-- STEP 2: Run while connected to the 'datawarehouse' database
-- =============================================================

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;
