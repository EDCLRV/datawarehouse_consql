/*
===============================================================================
TRANSFORMACIÓN DE CLIENTES EN LA CAPA PLATA
Motor: PostgreSQL
Tabla: plata.crm_cust_info

No lee ni modifica las tablas de bronce.
No vacía ni vuelve a cargar la tabla de plata.
===============================================================================
*/

\set ON_ERROR_STOP on
\timing on

BEGIN;

-- Evitar modificaciones simultáneas durante esta transformación.
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

COMMIT;

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
\echo 'FINALIZADO: TRANSFORMACIONES GUARDADAS EN PLATA'
\echo '============================================================'