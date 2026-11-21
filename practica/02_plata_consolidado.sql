/*
DDL Y CARGA CRM DEL ESQUEMA PLATA - PostgreSQL / psql

ADVERTENCIA: vacía y recarga las tres tablas CRM de plata.
Bronce no se modifica. ERP: solo DDL, sin carga.
Las tablas existentes deben tener una estructura compatible.
Fechas: longitud y rango no garantizan validez de mes/día.
Pendientes: precios nulos/cero, cantidades inválidas, costos negativos
 y corrección de inconsistencias cronológicas.
*/
\set ON_ERROR_STOP on
\timing on
BEGIN;
CREATE SCHEMA IF NOT EXISTS plata;

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

CREATE TABLE IF NOT EXISTS plata.erp_loc_a101 (
    cid VARCHAR(50),
    cntry VARCHAR(50),
    dwh_create_date TIMESTAMP DEFAULT LOCALTIMESTAMP
);

CREATE TABLE IF NOT EXISTS plata.erp_cust_az12 (
    cid VARCHAR(50),
    bdate DATE,
    gen VARCHAR(50),
    dwh_create_date TIMESTAMP DEFAULT LOCALTIMESTAMP
);

CREATE TABLE IF NOT EXISTS plata.erp_px_cat_g1v2 (
    id VARCHAR(50),
    cat VARCHAR(50),
    subcat VARCHAR(50),
    maintenance VARCHAR(50),
    dwh_create_date TIMESTAMP DEFAULT LOCALTIMESTAMP
);

-- Recarga CRM: no se utilizan CASCADE ni DROP.
TRUNCATE TABLE plata.crm_sales_details, plata.crm_prd_info, plata.crm_cust_info;

-- Cargar clientes antes de aplicar la transformación original sobre plata.
INSERT INTO plata.crm_cust_info (cst_id, cst_key, cst_firstname, cst_lastname, cst_marital_status, cst_gndr, cst_create_date)
SELECT cst_id, cst_key, cst_firstname, cst_lastname, cst_marital_status, cst_gndr, cst_create_date
FROM bronce.crm_cust_info;

-- Lógica del script original de clientes: se conserva DELETE, UPDATE,
-- bloqueo, desempate por ctid y reconocimiento de valores ya normalizados.
LOCK TABLE plata.crm_cust_info IN SHARE ROW EXCLUSIVE MODE;

\echo '============================================================'
\echo 'INICIO: TRANSFORMACIÓN DE plata.crm_cust_info'
\echo '============================================================'

-- ============================================================================
-- 1. CONSERVAR UNA FILA POR CLIENTE
-- ============================================================================

\echo '[1/3] Conservando la fila más reciente de cada cliente...'

WITH clientes_numerados AS (
    SELECT
        ctid AS fila_id,
        ROW_NUMBER() OVER (
            PARTITION BY cst_id
            ORDER BY
                cst_create_date DESC NULLS LAST,
                ctid
        ) AS flag_last
    FROM plata.crm_cust_info
)
DELETE FROM plata.crm_cust_info AS crm
USING clientes_numerados AS num
WHERE crm.ctid = num.fila_id
  AND num.flag_last > 1;

-- ============================================================================
-- 2. LIMPIAR NOMBRES Y NORMALIZAR ESTADO CIVIL Y GÉNERO
-- ============================================================================

\echo '[2/3] Limpiando nombres, apellidos, estado civil y género...'

UPDATE plata.crm_cust_info
SET
    cst_firstname = TRIM(cst_firstname),

    cst_lastname = TRIM(cst_lastname),

    cst_marital_status = CASE
        WHEN cst_marital_status IS NULL THEN 'n/a'
        WHEN UPPER(TRIM(cst_marital_status)) IN ('S', 'SINGLE')
            THEN 'Single'
        WHEN UPPER(TRIM(cst_marital_status)) IN ('M', 'MARRIED')
            THEN 'Married'
        WHEN UPPER(TRIM(cst_marital_status)) = 'N/A'
            THEN 'n/a'
        ELSE UPPER(TRIM(cst_marital_status))
    END,

    cst_gndr = CASE
        WHEN cst_gndr IS NULL THEN 'n/a'
        WHEN UPPER(TRIM(cst_gndr)) IN ('F', 'FEMALE')
            THEN 'Female'
        WHEN UPPER(TRIM(cst_gndr)) IN ('M', 'MALE')
            THEN 'Male'
        WHEN UPPER(TRIM(cst_gndr)) = 'N/A'
            THEN 'n/a'
        ELSE UPPER(TRIM(cst_gndr))
    END;

-- ============================================================================
-- 3. VERIFICAR LOS RESULTADOS
-- ============================================================================

\echo '[3/3] Verificando resultados...'

SELECT COUNT(*) AS total_clientes
FROM plata.crm_cust_info;

-- Debe devolver cero filas si quedó una fila por identificador.
SELECT
    cst_id,
    COUNT(*) AS cantidad
FROM plata.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1;

-- Muestra de los datos transformados.
SELECT
    cst_id,
    cst_key,
    cst_firstname,
    cst_lastname,
    cst_marital_status,
    cst_gndr,
    cst_create_date,
    dwh_create_date
FROM plata.crm_cust_info
ORDER BY cst_id
LIMIT 20;

\echo '============================================================'
\echo 'CLIENTES TRANSFORMADOS; COMMIT AL FINAL DEL SCRIPT'
\echo '============================================================'

-- Carga de productos: solución final acordada.
INSERT INTO plata.crm_prd_info (
    prd_id, cat_id, prd_key, prd_nm, prd_cost, prd_line,
    prd_start_dt, prd_end_dt
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
    CAST(LEAD(prd_start_dt) OVER (
        PARTITION BY prd_key ORDER BY prd_start_dt ASC
    ) AS DATE) - 1
FROM bronce.crm_prd_info;

-- Carga de ventas: último ajuste propuesto, sin recuperar precios ausentes.
INSERT INTO plata.crm_sales_details (
    sls_ord_num, sls_prd_key, sls_cust_id,
    sls_order_dt, sls_ship_dt, sls_due_dt,
    sls_sales, sls_quantity, sls_price
)
SELECT
    TRIM(sls_ord_num), sls_prd_key, sls_cust_id,
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
         AND (sls_sales IS NULL OR sls_sales <= 0
              OR sls_sales <> sls_quantity * ABS(sls_price))
        THEN sls_quantity * ABS(sls_price)
        ELSE sls_sales
    END,
    sls_quantity,
    ABS(sls_price)
FROM bronce.crm_sales_details;

COMMIT;

-- CONTROLES: solo diagnóstico; no corrigen datos ni cancelan la carga.
SELECT 'crm_cust_info' AS tabla, COUNT(*) AS total FROM plata.crm_cust_info
UNION ALL SELECT 'crm_prd_info', COUNT(*) FROM plata.crm_prd_info
UNION ALL SELECT 'crm_sales_details', COUNT(*) FROM plata.crm_sales_details;

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

SELECT prd_id, prd_key, cat_id, prd_nm, prd_cost, prd_line,
       prd_start_dt, prd_end_dt
FROM plata.crm_prd_info
ORDER BY prd_start_dt ASC, prd_id ASC;
