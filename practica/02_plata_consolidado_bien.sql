/*
===============================================================================
PLATA: DDL Y RECARGA COMPLETA DE LAS CINCO TABLAS TRABAJADAS
PostgreSQL. Ejecutar con psql conectado a practicas_sql.

ADVERTENCIA: vacía y recarga las cinco tablas trabajadas de plata.
No modifica bronce. No usa DROP ni CASCADE.
erp_px_cat_g1v2: solo crea estructura; NO vacía ni carga esta tabla.
Las tablas preexistentes deben tener estructura compatible con este DDL.

Una transacción engloba DDL y carga. ON_ERROR_STOP detiene psql ante errores.
Si hay un error en una sesión interactiva, ejecutar ROLLBACK antes de reintentar.
Las consultas de control al final son diagnósticas, no bloquean la carga.

Limitaciones conservadas (no se inventan reglas):
- Ventas: precios nulos/cero y cantidades inválidas quedan pendientes.
- Fechas de ventas: longitud y rango no validan por sí solos mes/día.
  TO_DATE puede fallar o normalizar ciertas entradas; revisar los controles.
- Productos: costos negativos y fechas de inicio repetidas requieren revisión.
- Clientes: se conserva desempate por ctid del script original.
- No se eliminan filas de ventas por claves sin correspondencia.
===============================================================================
*/
\set ON_ERROR_STOP on
\timing on

BEGIN;
CREATE SCHEMA IF NOT EXISTS plata;

-- 1. DDL

CREATE TABLE IF NOT EXISTS plata.crm_cust_info (
    cst_id INTEGER,
    cst_key VARCHAR(50),
    cst_firstname VARCHAR(50),
    cst_lastname VARCHAR(50),
    cst_marital_status VARCHAR(50),
    cst_gndr VARCHAR(50),
    cst_create_date DATE,
    dwh_create_date TIMESTAMP DEFAULT LOCALTIMESTAMP
);

CREATE TABLE IF NOT EXISTS plata.crm_prd_info (
    prd_id INTEGER,
    cat_id VARCHAR(50),
    prd_key VARCHAR(50),
    prd_nm VARCHAR(50),
    prd_cost INTEGER,
    prd_line VARCHAR(50),
    prd_start_dt DATE,
    prd_end_dt DATE,
    dwh_create_date TIMESTAMP DEFAULT LOCALTIMESTAMP
);

CREATE TABLE IF NOT EXISTS plata.crm_sales_details (
    sls_ord_num VARCHAR(50),
    sls_prd_key VARCHAR(50),
    sls_cust_id INTEGER,
    sls_order_dt DATE,
    sls_ship_dt DATE,
    sls_due_dt DATE,
    sls_sales INTEGER,
    sls_quantity INTEGER,
    sls_price INTEGER,
    dwh_create_date TIMESTAMP DEFAULT LOCALTIMESTAMP
);

CREATE TABLE IF NOT EXISTS plata.erp_cust_az12 (
    cid VARCHAR(50),
    bdate DATE,
    gen VARCHAR(50),
    dwh_create_date TIMESTAMP DEFAULT LOCALTIMESTAMP
);

CREATE TABLE IF NOT EXISTS plata.erp_loc_a101 (
    cid VARCHAR(50),
    cntry VARCHAR(50),
    dwh_create_date TIMESTAMP DEFAULT LOCALTIMESTAMP
);

CREATE TABLE IF NOT EXISTS plata.erp_px_cat_g1v2 (
    id VARCHAR(50),
    cat VARCHAR(50),
    subcat VARCHAR(50),
    maintenance VARCHAR(50),
    dwh_create_date TIMESTAMP DEFAULT LOCALTIMESTAMP
);

-- 2. RECARGA: solo las cinco tablas trabajadas.
TRUNCATE TABLE
    plata.crm_cust_info,
    plata.crm_prd_info,
    plata.crm_sales_details,
    plata.erp_cust_az12,
    plata.erp_loc_a101;

-- 3. CLIENTES CRM: cargar y aplicar la lógica del script original.
INSERT INTO plata.crm_cust_info (
    cst_id, cst_key, cst_firstname, cst_lastname,
    cst_marital_status, cst_gndr, cst_create_date
)
SELECT
    cst_id, cst_key, cst_firstname, cst_lastname,
    cst_marital_status, cst_gndr, cst_create_date
FROM bronce.crm_cust_info;

LOCK TABLE plata.crm_cust_info IN SHARE ROW EXCLUSIVE MODE;

WITH clientes_numerados AS (
    SELECT
        ctid AS fila_id,
        ROW_NUMBER() OVER (
            PARTITION BY cst_id
            ORDER BY cst_create_date DESC NULLS LAST, ctid
        ) AS flag_last
    FROM plata.crm_cust_info
)
DELETE FROM plata.crm_cust_info AS crm
USING clientes_numerados AS num
WHERE crm.ctid = num.fila_id
  AND num.flag_last > 1;

UPDATE plata.crm_cust_info
SET
    cst_firstname = TRIM(cst_firstname),
    cst_lastname = TRIM(cst_lastname),
    cst_marital_status = CASE
        WHEN cst_marital_status IS NULL THEN 'n/a'
        WHEN UPPER(TRIM(cst_marital_status)) IN ('S', 'SINGLE') THEN 'Single'
        WHEN UPPER(TRIM(cst_marital_status)) IN ('M', 'MARRIED') THEN 'Married'
        WHEN UPPER(TRIM(cst_marital_status)) = 'N/A' THEN 'n/a'
        ELSE UPPER(TRIM(cst_marital_status))
    END,
    cst_gndr = CASE
        WHEN cst_gndr IS NULL THEN 'n/a'
        WHEN UPPER(TRIM(cst_gndr)) IN ('F', 'FEMALE') THEN 'Female'
        WHEN UPPER(TRIM(cst_gndr)) IN ('M', 'MALE') THEN 'Male'
        WHEN UPPER(TRIM(cst_gndr)) = 'N/A' THEN 'n/a'
        ELSE UPPER(TRIM(cst_gndr))
    END;

-- 4. PRODUCTOS CRM
-- No conservar prd_end_dt original ni agregar prd_end_dt_test.
INSERT INTO plata.crm_prd_info (
    prd_id, cat_id, prd_key, prd_nm, prd_cost,
    prd_line, prd_start_dt, prd_end_dt
)
SELECT
    prd_id,
    REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_'),
    SUBSTRING(prd_key FROM 7),
    TRIM(prd_nm),
    COALESCE(prd_cost, 0),
    CASE
        WHEN prd_line IS NULL THEN 'n/a'
        WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
        WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
        WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'
        WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
        ELSE UPPER(TRIM(prd_line))
    END,
    CAST(prd_start_dt AS DATE),
    CAST(
        LEAD(prd_start_dt) OVER (
            PARTITION BY prd_key
            ORDER BY prd_start_dt ASC
        ) AS DATE
    ) - 1
FROM bronce.crm_prd_info;

-- 5. VENTAS CRM
INSERT INTO plata.crm_sales_details (
    sls_ord_num, sls_prd_key, sls_cust_id,
    sls_order_dt, sls_ship_dt, sls_due_dt,
    sls_sales, sls_quantity, sls_price
)
SELECT
    TRIM(sls_ord_num),
    sls_prd_key,
    sls_cust_id,
    CASE
        WHEN sls_order_dt <= 0
          OR LENGTH(sls_order_dt::text) <> 8
          OR sls_order_dt < 19000101
          OR sls_order_dt > 20500101
        THEN NULL
        ELSE TO_DATE(sls_order_dt::text, 'YYYYMMDD')
    END,
    CASE
        WHEN sls_ship_dt <= 0
          OR LENGTH(sls_ship_dt::text) <> 8
          OR sls_ship_dt < 19000101
          OR sls_ship_dt > 20500101
        THEN NULL
        ELSE TO_DATE(sls_ship_dt::text, 'YYYYMMDD')
    END,
    CASE
        WHEN sls_due_dt <= 0
          OR LENGTH(sls_due_dt::text) <> 8
          OR sls_due_dt < 19000101
          OR sls_due_dt > 20500101
        THEN NULL
        ELSE TO_DATE(sls_due_dt::text, 'YYYYMMDD')
    END,
    CASE
        WHEN sls_quantity > 0
         AND sls_price IS NOT NULL
         AND sls_price <> 0
         AND (
             sls_sales IS NULL
             OR sls_sales <= 0
             OR sls_sales <> sls_quantity * ABS(sls_price)
         )
        THEN sls_quantity * ABS(sls_price)
        ELSE sls_sales
    END,
    sls_quantity,
    ABS(sls_price)
FROM bronce.crm_sales_details;

-- 6. CLIENTES ERP
-- Fechas anteriores a 1924 se conservan: solo se anulan fechas futuras.
INSERT INTO plata.erp_cust_az12 (cid, bdate, gen)
SELECT
    CASE
        WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid FROM 4)
        ELSE cid
    END,
    CASE
        WHEN bdate > CURRENT_DATE THEN NULL
        ELSE bdate
    END,
    CASE
        WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
        WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
        ELSE 'n/a'
    END
FROM bronce.erp_cust_az12;

-- 7. UBICACIONES ERP
-- REPLACE elimina todos los guiones. TRIM conserva espacios internos.
INSERT INTO plata.erp_loc_a101 (cid, cntry)
SELECT
    REPLACE(cid, '-', ''),
    CASE
        WHEN TRIM(cntry) = 'DE' THEN 'Germany'
        WHEN TRIM(cntry) IN ('US', 'USA') THEN 'United States'
        WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
        ELSE TRIM(cntry)
    END
FROM bronce.erp_loc_a101;

COMMIT;

-- 8. CONTROLES POSTERIORES: solo lectura.
-- Los resultados con incidencias deben revisarse; no se corrigen aquí.

-- 8.1 Conteos de origen y destino. Clientes CRM se deduplican.
SELECT 'crm_cust_info' AS tabla,
    (SELECT COUNT(*) FROM bronce.crm_cust_info) AS registros_bronce,
    (SELECT COUNT(*) FROM plata.crm_cust_info) AS registros_plata
UNION ALL
SELECT 'crm_prd_info' AS tabla,
    (SELECT COUNT(*) FROM bronce.crm_prd_info) AS registros_bronce,
    (SELECT COUNT(*) FROM plata.crm_prd_info) AS registros_plata
UNION ALL
SELECT 'crm_sales_details' AS tabla,
    (SELECT COUNT(*) FROM bronce.crm_sales_details) AS registros_bronce,
    (SELECT COUNT(*) FROM plata.crm_sales_details) AS registros_plata
UNION ALL
SELECT 'erp_cust_az12' AS tabla,
    (SELECT COUNT(*) FROM bronce.erp_cust_az12) AS registros_bronce,
    (SELECT COUNT(*) FROM plata.erp_cust_az12) AS registros_plata
UNION ALL
SELECT 'erp_loc_a101' AS tabla,
    (SELECT COUNT(*) FROM bronce.erp_loc_a101) AS registros_bronce,
    (SELECT COUNT(*) FROM plata.erp_loc_a101) AS registros_plata;

-- 8.2 Clientes duplicados y muestra de clientes.
SELECT cst_id, COUNT(*) AS cantidad
FROM plata.crm_cust_info
GROUP BY cst_id HAVING COUNT(*) > 1;

SELECT cst_id, cst_key, cst_firstname, cst_lastname,
       cst_marital_status, cst_gndr, cst_create_date, dwh_create_date
FROM plata.crm_cust_info ORDER BY cst_id LIMIT 20;

-- 8.3 Productos: revisión del resultado y posibles intervalos inválidos.
SELECT prd_id, cat_id, prd_key, prd_nm, prd_cost, prd_line,
       prd_start_dt, prd_end_dt, dwh_create_date
FROM plata.crm_prd_info
ORDER BY prd_start_dt ASC, prd_id ASC;

SELECT prd_key, prd_start_dt, prd_end_dt
FROM plata.crm_prd_info
WHERE prd_end_dt < prd_start_dt;

SELECT prd_id, prd_cost FROM plata.crm_prd_info WHERE prd_cost < 0;

-- 8.4 Ventas: espacios, relaciones, cronología y fechas nulas.
SELECT sls_ord_num FROM plata.crm_sales_details
WHERE sls_ord_num <> TRIM(sls_ord_num);

SELECT DISTINCT s.sls_prd_key
FROM plata.crm_sales_details AS s
WHERE NOT EXISTS (
    SELECT 1 FROM plata.crm_prd_info AS p
    WHERE p.prd_key = s.sls_prd_key
);

SELECT DISTINCT s.sls_cust_id
FROM plata.crm_sales_details AS s
WHERE NOT EXISTS (
    SELECT 1 FROM plata.crm_cust_info AS c
    WHERE c.cst_id = s.sls_cust_id
);

SELECT sls_ord_num, sls_order_dt, sls_ship_dt, sls_due_dt
FROM plata.crm_sales_details
WHERE sls_order_dt > sls_ship_dt OR sls_order_dt > sls_due_dt;

SELECT sls_ord_num, sls_order_dt, sls_ship_dt, sls_due_dt
FROM plata.crm_sales_details
WHERE sls_order_dt IS NULL OR sls_ship_dt IS NULL OR sls_due_dt IS NULL;

SELECT DISTINCT sls_sales, sls_quantity, sls_price
FROM plata.crm_sales_details
WHERE sls_sales <> sls_quantity * sls_price
   OR sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL
   OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
ORDER BY sls_sales ASC NULLS FIRST,
         sls_quantity ASC NULLS FIRST,
         sls_price ASC NULLS FIRST;

-- 8.5 Clientes ERP: reglas aplicadas y relaciones con cst_key, no cst_id.
SELECT cid FROM plata.erp_cust_az12 WHERE cid LIKE 'NAS%';
SELECT DISTINCT bdate FROM plata.erp_cust_az12
WHERE bdate > CURRENT_DATE ORDER BY bdate;
SELECT DISTINCT gen FROM plata.erp_cust_az12 ORDER BY gen;

SELECT DISTINCT e.cid
FROM plata.erp_cust_az12 AS e
WHERE NOT EXISTS (
    SELECT 1 FROM plata.crm_cust_info AS c WHERE c.cst_key = e.cid
);

-- 8.6 Ubicaciones ERP.
SELECT cid FROM plata.erp_loc_a101 WHERE cid LIKE '%-%';
SELECT DISTINCT cntry FROM plata.erp_loc_a101 ORDER BY cntry NULLS FIRST;

SELECT DISTINCT e.cid
FROM plata.erp_loc_a101 AS e
WHERE NOT EXISTS (
    SELECT 1 FROM plata.crm_cust_info AS c WHERE c.cst_key = e.cid
);

-- ERP_PX_CAT_G1V2: carga pendiente; no se inventan transformaciones.
