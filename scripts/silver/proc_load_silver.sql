/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to 
    populate the 'silver' schema tables from the 'bronze' schema.
	Actions Performed:
		- Truncates Silver tables.
		- Inserts transformed and cleansed data from Bronze into Silver tables.
		
Parameters:
    None. 
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC Silver.load_silver;
===============================================================================
*/
/**********************CRM TABLES*****************/
--Use Datawarehouse;


CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
DECLARE @start_time DATETIME, @end_time DATETIME , @batch_start_time DATETIME, @batch_end_time DATETIME;
BEGIN TRY
	set @batch_start_time = GETDATE();
	PRINT '===================================================================';
	PRINT'LOAD SILVER LAYER';
	PRINT '===================================================================';

	PRINT '-------------------------------------------------------------------';
	PRINT 'LOADING CRM TABLES';
	PRINT '-------------------------------------------------------------------';

	set @start_time = GETDATE();

	PRINT '>>TRUNCATIG THE TABLE silver.crm_cust_info'
	TRUNCATE TABLE silver.crm_cust_info
	PRINT '>>INSERTING DATA INTO silver.crm_cust_info'
		INSERT INTO silver.crm_cust_info(
		CST_ID,
		cst_key,
		cst_firstname,
		cst_lastname,
		cst_marital_status,
		cst_gndr,
		cst_create_date)
		SELECT 
		cst_id,
		cst_key,
		--2- TRIM SPACE
		TRIM(CST_FIRSTNAME) AS cst_irstname,
		TRIM(CST_LASTNAME) AS cst_lastname,
		--3- DATA STANDARLIZATI ON
		CASE WHEN UPPER(TRIM(CST_MARITAL_STATUS)) = 'M' THEN 'Married'
		     WHEN UPPER(TRIM(CST_MARITAL_STATUS)) = 'S' THEN 'Single'
		     ELSE 'N/A'
		     END CST_MARITAL_STATUS,
		CASE WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
		     WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
		     ELSE 'N/A'
		     END CST_GNDR,
		     cst_create_date

		FROM(
		SELECT *,
		--1- PK 
		RANK() OVER(PARTITION BY CST_ID ORDER BY CST_CREATE_DATE DESC) AS FLAG_LAST
		FROM bronze.crm_cust_info
		WHERE cst_id IS NOT NULL)T
		WHERE FLAG_LAST = 1;
	      set @end_time =GETDATE();
	      PRINT 'LOAD DURATION:' + cast(DATEDIFF(second , @start_time, @end_time)as nvarchar)+ 'seconds';
	      PRINT '<<-----------------';
	
	set @start_time = GETDATE();
	PRINT '>>TRUNCATIG THE TABLE silver.crm_prd_info'
	TRUNCATE TABLE silver.crm_prd_info
	PRINT '>>INSERTING DATA INTO silver.crm_prd_info'
	insert into silver.crm_prd_info(
		prd_id,
		cat_id,
		prd_key,
		prd_nm,
		prd_cost,
		prd_line,
		prd_start_dt,
		prd_end_dt
		)
	Select
		prd_id,
		REPLACE(SUBSTRING(PRD_KEY , 1, 5), '-' ,'_') AS cat_id,--extract categiry id
		SUBSTRING(PRD_KEY , 7 , LEN(PRD_KEY)) AS prd_key,--extract prodcut key 
		prd_nm,
		COALESCE(PRD_COST , 0)prd_cost,
	CASE UPPER(TRIM(prd_line))
	     WHEN 'M' THEN 'MOUNTAIN'
	     WHEN 'R' THEN 'ROAD'
	     WHEN 'S' THEN 'OTHER SALES'
	     WHEN 'T' THEN  'TOURING'
	     ELSE 'N/A'
	     END prd_line, --map proudct lines codes to perspective values
	CAST(prd_start_dt AS DATE) as prd_start_dt,
	CAST(LEAD(prd_start_dt) OVER(PARTITION BY PRD_KEY ORDER BY PRD_START_DT)-1
	AS DATE) AS prd_end_dt --calucluate end date as one day before the next start date
	from bronze.crm_prd_info;
	set @end_time = GETDATE();
	print 'LOAD DURATION:' + cast(DATEDIFF(second , @start_time, @end_time) as nvarchar) + 'seconds';
	PRINT '>> ------------';

	set @start_time = GETDATE();

	PRINT '>>TRUNCATIG THE TABLE silver.crm_sales_details'
	TRUNCATE TABLE silver.crm_sales_details
	PRINT '>>INSERTING DATA INTO silver.crm_sales_details'
	INSERT INTO silver.crm_sales_details(
		sls_ord_num,
		sls_prd_key,
		sls_cust_id,
		sls_order_dt,
		sls_shipdt,
		sls_due_dt,
		sls_sales,
		sls_quantity,
		sls_price
		)
	SELECT 
	sls_ord_num,
	sls_prd_key,
	sls_cust_id,
	CASE 
	    WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL
	    ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
	END AS sls_order_dt,
	CASE 
	    WHEN sls_shipdt = 0 OR LEN(sls_shipdt) != 8 THEN NULL
	    ELSE CAST(CAST(sls_shipdt AS VARCHAR) AS DATE)
	END AS sls_ship_dt,
	CASE 
	    WHEN sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL
	    ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
	END AS sls_due_dt,
	CASE 
		WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price) 
		THEN sls_quantity * ABS(sls_price)
		ELSE sls_sales
	END AS sls_sales, -- Recalculate sales if original value is missing or incorrect
	sls_quantity,
	CASE 
		WHEN sls_price IS NULL OR sls_price <= 0 
		THEN sls_sales / NULLIF(sls_quantity, 0)
		ELSE sls_price  -- Derive price if original value is invalid
	END AS sls_price
	FROM bronze.crm_sales_details;
	set @end_time =GETDATE();

	PRINT 'LOAD DURATION:' + cast(DATEDIFF(second , @start_time, @end_time)as nvarchar)+ 'seconds';
	PRINT '<<-----------------';

	PRINT '-------------------------------------------------------------------';
	PRINT 'LOADING ERP TABLES';
	PRINT '-------------------------------------------------------------------';

	set @start_time = GETDATE();

	/**********************ERP TABLES*****************/
	PRINT '>>TRUNCATIG THE TABLE silver.erp_cust_az12'
	TRUNCATE TABLE silver.erp_cust_az12
	PRINT '>>INSERTING DATA INTO silver.erp_cust_az12'
	INSERT INTO silver.erp_cust_az12(
	cid,
	bdate,
	gen)
	SELECT 
	CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid , 4, LEN(CID))
	ELSE cid
	END cid,
	CASE WHEN bdate > GETDATE() THEN NULL
	ELSE bdate
	END bdate,
	CASE WHEN UPPER(TRIM(GEN)) IN ('F' , 'FEMALE') THEN 'Female'
	     WHEN UPPER(TRIM(GEN)) IN ('M' , 'MALE') THEN   'Male'
	     ELSE 'N/A'
	END gen
	FROM bronze.erp_cust_az12
      set @end_time =GETDATE();
	PRINT 'LOAD DURATION:' + cast(DATEDIFF(second , @start_time, @end_time)as nvarchar)+ 'seconds';
	PRINT '<<-----------------';

	set @start_time = GETDATE();

	PRINT '>>TRUNCATING THE TABLE silver.erp_loc_a101'
	TRUNCATE TABLE silver.erp_loc_a101 
	PRINT '>>INSERTING DATA INTO silver.erp_loc_a101'
	INSERT INTO silver.erp_loc_a101(
	cid,
	cntry)

	SELECT 
	REPLACE(CID , '-' ,'') AS cid,
	CASE WHEN TRIM(cntry) = 'DE' THEN 'Germany'
	     WHEN TRIM(cntry) IN ('US', 'USA') THEN 'United States'
	     WHEN TRIM(cntry) = ' ' OR cntry IS NULL THEN 'N/A'
	     ELSE TRIM(cntry)
	END cntry
	FROM bronze.erp_loc_a101
      set @end_time =GETDATE();
	PRINT 'LOAD DURATION:' + cast(DATEDIFF(second , @start_time, @end_time)as nvarchar)+ 'seconds';
	PRINT '<<-----------------';

	set @start_time = GETDATE();

	PRINT '>>TRUNCATING THE TABLE silver.erp_px_cat_g1v2'
	TRUNCATE TABLE silver.erp_px_cat_g1v2 
	PRINT '>>INSERTING DATA INTO silver.erp_px_cat_g1v2'
	INSERT INTO silver.erp_px_cat_g1v2(
	id,
	cat,
	subcat,
	maintenance
	)
	SELECT 
	id,
	cat,
	subcat,
	maintenance
	FROM bronze.erp_px_cat_g1v2;
	set @end_time =GETDATE();
	PRINT 'LOAD DURATION:' + cast(DATEDIFF(second , @start_time, @end_time)as nvarchar)+ 'seconds';
	PRINT '<<-----------------';

	set @batch_end_time = GETDATE();
	PRINT 'LOAD DURATION OF SILVER LAYER : ' + CAST(DATEDIFF(SECOND , @batch_start_time , @batch_end_time) AS NVARCHAR) + 'SECONDS';
      PRINT '--------------------'

END TRY
BEGIN CATCH
	PRINT '===============================================';
	PRINT 'ERROR OCCURED AT LOADING SILVER LAYER';
	PRINT 'ERROR MESSAGE :'+ ERROR_MESSAGE();
	PRINT 'ERROR MESSAGE :'+ CAST(ERROR_NUMBER() AS NVARCHAR);
	PRINT 'ERROR MESSAGE :'+CAST(ERROR_STATE() AS NVARCHAR);
	PRINT '===============================================';
	END CATCH

END;
