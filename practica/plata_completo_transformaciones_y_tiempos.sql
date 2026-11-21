/*
===============================================================================
SCRIPT FINAL: BRONCE -> PLATA
PostgreSQL / psql. Base de trabajo: practicas_sql.

Incluye en un solo archivo:
1. DDL de las seis tablas de plata.
2. Vaciado y carga de las seis tablas con nuestras consultas.
3. Transformación de clientes del archivo 03_transformar_crm_cust_info.sql.
4. Temporizador por tabla, tiempo de cada sentencia y tiempo total.
5. Consultas finales de control, sin modificar datos.

No usa procedimiento almacenado ni CALL.
ADVERTENCIA: al ejecutarlo se vacían y recargan las SEIS tablas de plata.
No se modifica bronce. No se utiliza DROP ni CASCADE.
CREATE TABLE IF NOT EXISTS no modifica la estructura de tablas existentes:
las tablas que ya existan deben ser compatibles con este DDL.

Se conserva nuestra lógica, no las reglas diferentes del procedimiento anexo:
- Clientes: no se añade filtro de cst_id nulo; se usa el script original.
- Productos: LEAD por prd_key, convertir a DATE y restar un día.
- Ventas: rango 19000101..20500101 y precio negativo con ABS.
- No se incorpora la derivación del precio de ventas/cantidad del anexo.
- erp_px_cat_g1v2: carga directa acordada.

Limitaciones pendientes (no se inventan correcciones):
- Fechas de ventas: longitud y rango no comprueban mes/día válidos.
  TO_DATE puede fallar o normalizar ciertas entradas.
- Ventas: no se reconstruyen precios nulos/cero ni cantidades inválidas.
- No se corrige automáticamente cronología ni relaciones sin correspondencia.
- Productos: costos negativos e inicios repetidos requieren revisión.
- Clientes: se conserva el desempate por ctid del script original.

Ejecución:
- Usar psql, no un editor SQL que no reconozca comandos de barra invertida.
- Ejecutar sin otra transacción abierta.
- ON_ERROR_STOP detiene el archivo si aparece un error.
- Si falla en una sesión interactiva, ejecutar ROLLBACK; antes de reintentar.
- Una sola transacción engloba DDL y las seis cargas.
- Las validaciones finales son diagnósticas: no cancelan la carga confirmada.

Tiempos:
- Por tabla: desde antes de TRUNCATE hasta finalizar su transformación.
- Total: incluye DDL, las seis cargas y COMMIT; excluye controles posteriores.
===============================================================================
*/
\set ON_ERROR_STOP on
\timing on

\echo '============================================================'
\echo 'INICIO: CARGA COMPLETA DE PLATA'
\echo '============================================================'

SELECT clock_timestamp() AS inicio_total \gset

BEGIN;

-- ============================================================================
-- 0. DDL: ESQUEMA Y TABLAS
-- ============================================================================
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

-- ============================================================================
-- 1. CRM_CUST_INFO
-- ============================================================================
\echo 'Cargando plata.crm_cust_info'

SELECT clock_timestamp() AS inicio_tabla \gset

TRUNCATE TABLE plata.crm_cust_info;

-- Cargar los datos de origen y aplicar nuestra transformación original.
INSERT INTO plata.crm_cust_info (
    cst_id, cst_key, cst_firstname, cst_lastname,
    cst_marital_status, cst_gndr, cst_create_date
)
SELECT
    cst_id, cst_key, cst_firstname, cst_lastname,
    cst_marital_status, cst_gndr, cst_create_date
FROM bronce.crm_cust_info;

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



SELECT
    'plata.crm_cust_info' AS tabla,
    ROUND(
        EXTRACT(EPOCH FROM (clock_timestamp() - :'inicio_tabla'::timestamptz))::numeric,
        3
    ) AS segundos;

-- ============================================================================
-- 2. CRM_PRD_INFO
-- ============================================================================
\echo 'Cargando plata.crm_prd_info'

SELECT clock_timestamp() AS inicio_tabla \gset

TRUNCATE TABLE plata.crm_prd_info;

-- No se conserva prd_end_dt original ni se agrega prd_end_dt_test.
-- El último registro de cada producto queda con prd_end_dt NULL.
INSERT INTO plata.crm_prd_info (
    prd_id,
    cat_id,
    prd_key,
    prd_nm,
    prd_cost,
    prd_line,
    prd_start_dt,
    prd_end_dt
)
SELECT
    prd_id,
    REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,
    SUBSTRING(prd_key FROM 7) AS prd_key,
    TRIM(prd_nm) AS prd_nm,
    COALESCE(prd_cost, 0) AS prd_cost,
    CASE
        WHEN prd_line IS NULL THEN 'n/a'
        WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
        WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
        WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'
        WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
        ELSE UPPER(TRIM(prd_line))
    END AS prd_line,
    CAST(prd_start_dt AS DATE) AS prd_start_dt,
    CAST(
        LEAD(prd_start_dt) OVER (
            PARTITION BY prd_key
            ORDER BY prd_start_dt ASC
        ) AS DATE
    ) - 1 AS prd_end_dt
FROM bronce.crm_prd_info;

SELECT
    'plata.crm_prd_info' AS tabla,
    ROUND(
        EXTRACT(EPOCH FROM (clock_timestamp() - :'inicio_tabla'::timestamptz))::numeric,
        3
    ) AS segundos;

-- ============================================================================
-- 3. CRM_SALES_DETAILS
-- ============================================================================
\echo 'Cargando plata.crm_sales_details'

SELECT clock_timestamp() AS inicio_tabla \gset

TRUNCATE TABLE plata.crm_sales_details;

-- Fechas: límites incluidos, entre 19000101 y 20500101.
-- Ventas: recalcular solo cuando hay cantidad y precio utilizables.
-- Los precios nulos/cero y cantidades inválidas siguen pendientes de regla.
INSERT INTO plata.crm_sales_details (
    sls_ord_num,
    sls_prd_key,
    sls_cust_id,
    sls_order_dt,
    sls_ship_dt,
    sls_due_dt,
    sls_sales,
    sls_quantity,
    sls_price
)
SELECT
    TRIM(sls_ord_num) AS sls_ord_num,
    sls_prd_key,
    sls_cust_id,
    CASE
        WHEN sls_order_dt <= 0
          OR LENGTH(sls_order_dt::text) <> 8
          OR sls_order_dt < 19000101
          OR sls_order_dt > 20500101
        THEN NULL
        ELSE TO_DATE(sls_order_dt::text, 'YYYYMMDD')
    END AS sls_order_dt,
    CASE
        WHEN sls_ship_dt <= 0
          OR LENGTH(sls_ship_dt::text) <> 8
          OR sls_ship_dt < 19000101
          OR sls_ship_dt > 20500101
        THEN NULL
        ELSE TO_DATE(sls_ship_dt::text, 'YYYYMMDD')
    END AS sls_ship_dt,
    CASE
        WHEN sls_due_dt <= 0
          OR LENGTH(sls_due_dt::text) <> 8
          OR sls_due_dt < 19000101
          OR sls_due_dt > 20500101
        THEN NULL
        ELSE TO_DATE(sls_due_dt::text, 'YYYYMMDD')
    END AS sls_due_dt,
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
    END AS sls_sales,
    sls_quantity,
    ABS(sls_price) AS sls_price
FROM bronce.crm_sales_details;

SELECT
    'plata.crm_sales_details' AS tabla,
    ROUND(
        EXTRACT(EPOCH FROM (clock_timestamp() - :'inicio_tabla'::timestamptz))::numeric,
        3
    ) AS segundos;

-- ============================================================================
-- 4. ERP_CUST_AZ12
-- ============================================================================
\echo 'Cargando plata.erp_cust_az12'

SELECT clock_timestamp() AS inicio_tabla \gset

TRUNCATE TABLE plata.erp_cust_az12;

-- cid se relaciona con cst_key, no directamente con cst_id.
-- Se conservan las fechas anteriores a 1924: solo se anulan las futuras.
INSERT INTO plata.erp_cust_az12 (
    cid,
    bdate,
    gen
)
SELECT
    CASE
        WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid FROM 4)
        ELSE cid
    END AS cid,
    CASE
        WHEN bdate > CURRENT_DATE THEN NULL
        ELSE bdate
    END AS bdate,
    CASE
        WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
        WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
        ELSE 'n/a'
    END AS gen
FROM bronce.erp_cust_az12;

SELECT
    'plata.erp_cust_az12' AS tabla,
    ROUND(
        EXTRACT(EPOCH FROM (clock_timestamp() - :'inicio_tabla'::timestamptz))::numeric,
        3
    ) AS segundos;

-- ============================================================================
-- 5. ERP_LOC_A101
-- ============================================================================
\echo 'Cargando plata.erp_loc_a101'

SELECT clock_timestamp() AS inicio_tabla \gset

TRUNCATE TABLE plata.erp_loc_a101;

-- REPLACE elimina todos los guiones.
-- TRIM elimina espacios de los extremos, no los espacios internos.
INSERT INTO plata.erp_loc_a101 (
    cid,
    cntry
)
SELECT
    REPLACE(cid, '-', '') AS cid,
    CASE
        WHEN TRIM(cntry) = 'DE' THEN 'Germany'
        WHEN TRIM(cntry) IN ('US', 'USA') THEN 'United States'
        WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
        ELSE TRIM(cntry)
    END AS cntry
FROM bronce.erp_loc_a101;

SELECT
    'plata.erp_loc_a101' AS tabla,
    ROUND(
        EXTRACT(EPOCH FROM (clock_timestamp() - :'inicio_tabla'::timestamptz))::numeric,
        3
    ) AS segundos;

-- ============================================================================
-- 6. ERP_PX_CAT_G1V2
-- ============================================================================
\echo 'Cargando plata.erp_px_cat_g1v2'

SELECT clock_timestamp() AS inicio_tabla \gset

TRUNCATE TABLE plata.erp_px_cat_g1v2;

-- Carga directa acordada después de las revisiones en PostgreSQL.
-- Sin TRIM, CASE, filtros ni DISTINCT: conservar los valores originales.
INSERT INTO plata.erp_px_cat_g1v2 (
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
FROM bronce.erp_px_cat_g1v2;

SELECT
    'plata.erp_px_cat_g1v2' AS tabla,
    ROUND(
        EXTRACT(EPOCH FROM (clock_timestamp() - :'inicio_tabla'::timestamptz))::numeric,
        3
    ) AS segundos;

COMMIT;

\echo '============================================================'
\echo 'CARGA DE LAS SEIS TABLAS CONFIRMADA'
\echo '============================================================'

SELECT
    ROUND(
        EXTRACT(EPOCH FROM (clock_timestamp() - :'inicio_total'::timestamptz))::numeric,
        3
    ) AS segundos_totales;

-- ============================================================================
-- 7. CONTROLES POSTERIORES: SOLO CONSULTA
-- ============================================================================

-- 7.1. Conteos. Clientes CRM se deduplican; los otros cinco se copian sin filtros.
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
    (SELECT COUNT(*) FROM plata.erp_loc_a101) AS registros_plata
UNION ALL
SELECT 'erp_px_cat_g1v2' AS tabla,
    (SELECT COUNT(*) FROM bronce.erp_px_cat_g1v2) AS registros_bronce,
    (SELECT COUNT(*) FROM plata.erp_px_cat_g1v2) AS registros_plata;

-- 7.2. Clientes CRM: duplicados y muestra.
SELECT cst_id, COUNT(*) AS cantidad
FROM plata.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1;

SELECT cst_id, cst_key, cst_firstname, cst_lastname,
       cst_marital_status, cst_gndr, cst_create_date, dwh_create_date
FROM plata.crm_cust_info
ORDER BY cst_id
LIMIT 20;

-- 7.3. Productos: muestra e intervalos inválidos. Fin NULL es esperado al final.
SELECT prd_id, cat_id, prd_key, prd_nm, prd_cost, prd_line,
       prd_start_dt, prd_end_dt, dwh_create_date
FROM plata.crm_prd_info
ORDER BY prd_start_dt ASC, prd_id ASC
LIMIT 1000;

SELECT prd_key, prd_start_dt, prd_end_dt
FROM plata.crm_prd_info
WHERE prd_end_dt < prd_start_dt;

SELECT prd_id, prd_cost
FROM plata.crm_prd_info
WHERE prd_cost < 0;

-- 7.4. Ventas: relaciones con productos y clientes.
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

-- Espacios residuales en el número de pedido.
SELECT sls_ord_num
FROM plata.crm_sales_details
WHERE sls_ord_num <> TRIM(sls_ord_num);

-- Pedidos posteriores a envío o vencimiento.
SELECT sls_ord_num, sls_order_dt, sls_ship_dt, sls_due_dt
FROM plata.crm_sales_details
WHERE sls_order_dt > sls_ship_dt
   OR sls_order_dt > sls_due_dt;

-- Fechas nulas tras la transformación.
SELECT sls_ord_num, sls_order_dt, sls_ship_dt, sls_due_dt
FROM plata.crm_sales_details
WHERE sls_order_dt IS NULL
   OR sls_ship_dt IS NULL
   OR sls_due_dt IS NULL;

-- Incidencias comerciales remanentes: requieren revisión.
SELECT DISTINCT sls_sales, sls_quantity, sls_price
FROM plata.crm_sales_details
WHERE sls_sales <> sls_quantity * sls_price
   OR sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL
   OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
ORDER BY sls_sales ASC NULLS FIRST,
         sls_quantity ASC NULLS FIRST,
         sls_price ASC NULLS FIRST;

-- 7.5. Clientes ERP: prefijo, fechas futuras, género y correspondencia con cst_key.
SELECT cid FROM plata.erp_cust_az12 WHERE cid LIKE 'NAS%';

SELECT DISTINCT bdate
FROM plata.erp_cust_az12
WHERE bdate > CURRENT_DATE
ORDER BY bdate;

SELECT DISTINCT gen FROM plata.erp_cust_az12 ORDER BY gen NULLS FIRST;

SELECT DISTINCT e.cid
FROM plata.erp_cust_az12 AS e
WHERE NOT EXISTS (
    SELECT 1 FROM plata.crm_cust_info AS c
    WHERE c.cst_key = e.cid
);

-- 7.6. Ubicaciones ERP.
SELECT cid FROM plata.erp_loc_a101 WHERE cid LIKE '%-%';
SELECT DISTINCT cntry FROM plata.erp_loc_a101 ORDER BY cntry NULLS FIRST;

SELECT DISTINCT e.cid
FROM plata.erp_loc_a101 AS e
WHERE NOT EXISTS (
    SELECT 1 FROM plata.crm_cust_info AS c
    WHERE c.cst_key = e.cid
);

-- 7.7. Categorías ERP: las revisiones se conservan solo como control.
SELECT * FROM plata.erp_px_cat_g1v2
WHERE cat <> TRIM(cat)
   OR subcat <> TRIM(subcat);

SELECT DISTINCT cat FROM plata.erp_px_cat_g1v2 ORDER BY cat NULLS FIRST;
SELECT DISTINCT subcat FROM plata.erp_px_cat_g1v2 ORDER BY subcat NULLS FIRST;
SELECT DISTINCT maintenance FROM plata.erp_px_cat_g1v2
ORDER BY maintenance NULLS FIRST;
