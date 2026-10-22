/*
=============================================================
Stored Procedure: Load Bronze Layer (Source -> Bronze)
=============================================================
Script Purpose:
    Loads the source CSV files into the 'bronze' tables.
    For each table it:
      - Truncates the table.
      - Loads the CSV file with COPY.
    It reports how long each table and the whole load took.

Parameters:
    base_path - folder that contains 'source_crm' and 'source_erp'.

Notes:
    - COPY reads files on the PostgreSQL server's machine, so the
      server must be able to read the folder. On macOS, the
      Downloads folder is often blocked; copy the datasets to
      /Users/Shared if you get "Permission denied".
    - COPY from a file requires superuser or the
      pg_read_server_files role.

Usage:
    CALL bronze.load_bronze();
    CALL bronze.load_bronze('/Users/Shared/01_datasets');
=============================================================
*/

CREATE OR REPLACE PROCEDURE bronze.load_bronze(
    base_path TEXT DEFAULT '/Users/calculator/Downloads/sql-data-warehouse-project/01_datasets'
)
LANGUAGE plpgsql
AS $$
DECLARE
    start_time        TIMESTAMP;
    end_time          TIMESTAMP;
    batch_start_time  TIMESTAMP;
    batch_end_time    TIMESTAMP;
    row_count         BIGINT;
    src               RECORD;
BEGIN
    batch_start_time := clock_timestamp();
    RAISE NOTICE '================================================';
    RAISE NOTICE 'Loading Bronze Layer';
    RAISE NOTICE '================================================';

    FOR src IN
        SELECT * FROM (VALUES
            (1, 'CRM', 'bronze.crm_cust_info',     'source_crm/cust_info.csv'),
            (2, 'CRM', 'bronze.crm_prd_info',      'source_crm/prd_info.csv'),
            (3, 'CRM', 'bronze.crm_sales_details', 'source_crm/sales_details.csv'),
            (4, 'ERP', 'bronze.erp_cust_az12',     'source_erp/CUST_AZ12.csv'),
            (5, 'ERP', 'bronze.erp_loc_a101',      'source_erp/LOC_A101.csv'),
            (6, 'ERP', 'bronze.erp_px_cat_g1v2',   'source_erp/PX_CAT_G1V2.csv')
        ) AS t(seq, source_system, table_name, file_name)
        ORDER BY seq
    LOOP
        start_time := clock_timestamp();
        RAISE NOTICE '------------------------------------------------';
        RAISE NOTICE '>> % | Truncating table: %', src.source_system, src.table_name;
        EXECUTE format('TRUNCATE TABLE %s', src.table_name);

        RAISE NOTICE '>> % | Loading data into: %', src.source_system, src.table_name;
        EXECUTE format(
            'COPY %s FROM %L WITH (FORMAT csv, HEADER true, DELIMITER %L)',
            src.table_name,
            base_path || '/' || src.file_name,
            ','
        );
        GET DIAGNOSTICS row_count = ROW_COUNT;

        end_time := clock_timestamp();
        RAISE NOTICE '>> Rows loaded: %', row_count;
        RAISE NOTICE '>> Load duration: % seconds',
            ROUND(EXTRACT(EPOCH FROM end_time - start_time)::NUMERIC, 3);
    END LOOP;

    batch_end_time := clock_timestamp();
    RAISE NOTICE '================================================';
    RAISE NOTICE 'Loading Bronze Layer is completed';
    RAISE NOTICE '   - Total load duration: % seconds',
        ROUND(EXTRACT(EPOCH FROM batch_end_time - batch_start_time)::NUMERIC, 3);
    RAISE NOTICE '================================================';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '================================================';
        RAISE NOTICE 'ERROR OCCURRED DURING LOADING BRONZE LAYER';
        RAISE NOTICE 'Error message: %', SQLERRM;
        RAISE NOTICE 'Error code: %', SQLSTATE;
        RAISE NOTICE '================================================';
        RAISE;
END;
$$;
