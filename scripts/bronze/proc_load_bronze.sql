/*
=============================================================
Stored Procedure: Load Bronze Layer (Source -> Bronze)
=============================================================
Script Purpose:
    Loads the source CSV files into the 'bronze' tables.
    For each table it:
      - Truncates the table.
      - Loads the CSV file with COPY.
    It reports the rows loaded and how long each table and the
    whole load took.

Notes:
    - COPY reads files on the PostgreSQL server's machine, so the
      server must be able to read the folder. On macOS, the
      Downloads folder is often blocked; copy the datasets to
      /Users/Shared and update the paths if you get
      "Permission denied".
    - COPY from a file requires superuser or the
      pg_read_server_files role.

Usage:
    CALL bronze.load_bronze();
=============================================================
*/

CREATE OR REPLACE PROCEDURE bronze.load_bronze()
LANGUAGE plpgsql
AS $$
DECLARE
    start_time        TIMESTAMP;
    end_time          TIMESTAMP;
    batch_start_time  TIMESTAMP;
    batch_end_time    TIMESTAMP;
    row_count         BIGINT;
BEGIN
    batch_start_time := clock_timestamp();
    RAISE NOTICE '================================================';
    RAISE NOTICE 'Loading Bronze Layer';
    RAISE NOTICE '================================================';

    -- =========================================================
    -- CRM
    -- =========================================================
    RAISE NOTICE '------------------------------------------------';
    RAISE NOTICE 'Loading CRM Tables';
    RAISE NOTICE '------------------------------------------------';

    -- crm_cust_info
    start_time := clock_timestamp();
    RAISE NOTICE '>> Truncating Table: bronze.crm_cust_info';
    TRUNCATE TABLE bronze.crm_cust_info;
    RAISE NOTICE '>> Inserting Data Into: bronze.crm_cust_info';
    COPY bronze.crm_cust_info
    FROM '/Users/calculator/Downloads/sql-data-warehouse-project/01_datasets/source_crm/cust_info.csv'
    WITH (FORMAT csv, HEADER true, DELIMITER ',');
    GET DIAGNOSTICS row_count = ROW_COUNT;
    end_time := clock_timestamp();
    RAISE NOTICE '>> Rows Loaded: %', row_count;
    RAISE NOTICE '>> Load Duration: % seconds', ROUND(EXTRACT(EPOCH FROM end_time - start_time)::NUMERIC, 3);
    RAISE NOTICE '>> -------------';

    -- crm_prd_info
    start_time := clock_timestamp();
    RAISE NOTICE '>> Truncating Table: bronze.crm_prd_info';
    TRUNCATE TABLE bronze.crm_prd_info;
    RAISE NOTICE '>> Inserting Data Into: bronze.crm_prd_info';
    COPY bronze.crm_prd_info
    FROM '/Users/calculator/Downloads/sql-data-warehouse-project/01_datasets/source_crm/prd_info.csv'
    WITH (FORMAT csv, HEADER true, DELIMITER ',');
    GET DIAGNOSTICS row_count = ROW_COUNT;
    end_time := clock_timestamp();
    RAISE NOTICE '>> Rows Loaded: %', row_count;
    RAISE NOTICE '>> Load Duration: % seconds', ROUND(EXTRACT(EPOCH FROM end_time - start_time)::NUMERIC, 3);
    RAISE NOTICE '>> -------------';

    -- crm_sales_details
    start_time := clock_timestamp();
    RAISE NOTICE '>> Truncating Table: bronze.crm_sales_details';
    TRUNCATE TABLE bronze.crm_sales_details;
    RAISE NOTICE '>> Inserting Data Into: bronze.crm_sales_details';
    COPY bronze.crm_sales_details
    FROM '/Users/calculator/Downloads/sql-data-warehouse-project/01_datasets/source_crm/sales_details.csv'
    WITH (FORMAT csv, HEADER true, DELIMITER ',');
    GET DIAGNOSTICS row_count = ROW_COUNT;
    end_time := clock_timestamp();
    RAISE NOTICE '>> Rows Loaded: %', row_count;
    RAISE NOTICE '>> Load Duration: % seconds', ROUND(EXTRACT(EPOCH FROM end_time - start_time)::NUMERIC, 3);
    RAISE NOTICE '>> -------------';

    -- =========================================================
    -- ERP
    -- =========================================================
    RAISE NOTICE '------------------------------------------------';
    RAISE NOTICE 'Loading ERP Tables';
    RAISE NOTICE '------------------------------------------------';

    -- erp_cust_az12
    start_time := clock_timestamp();
    RAISE NOTICE '>> Truncating Table: bronze.erp_cust_az12';
    TRUNCATE TABLE bronze.erp_cust_az12;
    RAISE NOTICE '>> Inserting Data Into: bronze.erp_cust_az12';
    COPY bronze.erp_cust_az12
    FROM '/Users/calculator/Downloads/sql-data-warehouse-project/01_datasets/source_erp/CUST_AZ12.csv'
    WITH (FORMAT csv, HEADER true, DELIMITER ',');
    GET DIAGNOSTICS row_count = ROW_COUNT;
    end_time := clock_timestamp();
    RAISE NOTICE '>> Rows Loaded: %', row_count;
    RAISE NOTICE '>> Load Duration: % seconds', ROUND(EXTRACT(EPOCH FROM end_time - start_time)::NUMERIC, 3);
    RAISE NOTICE '>> -------------';

    -- erp_loc_a101
    start_time := clock_timestamp();
    RAISE NOTICE '>> Truncating Table: bronze.erp_loc_a101';
    TRUNCATE TABLE bronze.erp_loc_a101;
    RAISE NOTICE '>> Inserting Data Into: bronze.erp_loc_a101';
    COPY bronze.erp_loc_a101
    FROM '/Users/calculator/Downloads/sql-data-warehouse-project/01_datasets/source_erp/LOC_A101.csv'
    WITH (FORMAT csv, HEADER true, DELIMITER ',');
    GET DIAGNOSTICS row_count = ROW_COUNT;
    end_time := clock_timestamp();
    RAISE NOTICE '>> Rows Loaded: %', row_count;
    RAISE NOTICE '>> Load Duration: % seconds', ROUND(EXTRACT(EPOCH FROM end_time - start_time)::NUMERIC, 3);
    RAISE NOTICE '>> -------------';

    -- erp_px_cat_g1v2
    start_time := clock_timestamp();
    RAISE NOTICE '>> Truncating Table: bronze.erp_px_cat_g1v2';
    TRUNCATE TABLE bronze.erp_px_cat_g1v2;
    RAISE NOTICE '>> Inserting Data Into: bronze.erp_px_cat_g1v2';
    COPY bronze.erp_px_cat_g1v2
    FROM '/Users/calculator/Downloads/sql-data-warehouse-project/01_datasets/source_erp/PX_CAT_G1V2.csv'
    WITH (FORMAT csv, HEADER true, DELIMITER ',');
    GET DIAGNOSTICS row_count = ROW_COUNT;
    end_time := clock_timestamp();
    RAISE NOTICE '>> Rows Loaded: %', row_count;
    RAISE NOTICE '>> Load Duration: % seconds', ROUND(EXTRACT(EPOCH FROM end_time - start_time)::NUMERIC, 3);
    RAISE NOTICE '>> -------------';

    batch_end_time := clock_timestamp();
    RAISE NOTICE '================================================';
    RAISE NOTICE 'Loading Bronze Layer is Completed';
    RAISE NOTICE '   - Total Load Duration: % seconds', ROUND(EXTRACT(EPOCH FROM batch_end_time - batch_start_time)::NUMERIC, 3);
    RAISE NOTICE '================================================';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '================================================';
        RAISE NOTICE 'ERROR OCCURRED DURING LOADING BRONZE LAYER';
        RAISE NOTICE 'Error Message: %', SQLERRM;
        RAISE NOTICE 'Error Code: %', SQLSTATE;
        RAISE NOTICE '================================================';
        RAISE;
END;
$$;
