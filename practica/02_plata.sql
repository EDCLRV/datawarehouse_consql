/*
===============================================================================
SCRIPT: CREACIÓN DE TABLAS DE LA CAPA PLATA
Motor: PostgreSQL
Esquema: plata

Objetivo:
    Crear las seis tablas de la capa plata e incorporar la columna
    dwh_create_date para registrar la fecha y hora de carga.

ADVERTENCIA:
    Este script elimina y vuelve a crear las tablas de plata.
    Los datos existentes en estas tablas se perderán.
    No modifica las tablas del esquema bronce.
===============================================================================
*/

\set ON_ERROR_STOP on
\timing on

\echo '============================================================'
\echo 'INICIO: CREACIÓN DE TABLAS DEL ESQUEMA PLATA'
\echo '============================================================'

BEGIN;

-- ============================================================================
-- 1. CREAR EL ESQUEMA
-- ============================================================================

\echo 'Comprobando el esquema plata'

CREATE SCHEMA IF NOT EXISTS plata;

-- ============================================================================
-- 2. INFORMACIÓN DE CLIENTES CRM
-- ============================================================================

\echo 'Creando plata.crm_cust_info'

DROP TABLE IF EXISTS plata.crm_cust_info;

CREATE TABLE plata.crm_cust_info (
    cst_id              INTEGER,
    cst_key             VARCHAR(50),
    cst_firstname       VARCHAR(50),
    cst_lastname        VARCHAR(50),
    cst_marital_status  VARCHAR(50),
    cst_gndr            VARCHAR(50),
    cst_create_date     DATE,
    dwh_create_date     TIMESTAMP DEFAULT LOCALTIMESTAMP
);

-- ============================================================================
-- 3. INFORMACIÓN DE PRODUCTOS CRM
-- ============================================================================

\echo 'Creando plata.crm_prd_info'

DROP TABLE IF EXISTS plata.crm_prd_info;

CREATE TABLE plata.crm_prd_info (
    prd_id              INTEGER,
    cat_id              VARCHAR(50),
    prd_key             VARCHAR(50),
    prd_nm              VARCHAR(50),
    prd_cost            INTEGER,
    prd_line            VARCHAR(50),
    prd_start_dt        DATE,
    prd_end_dt          DATE,
    dwh_create_date     TIMESTAMP DEFAULT LOCALTIMESTAMP
);

-- ============================================================================
-- 4. DETALLE DE VENTAS CRM
-- ============================================================================

\echo 'Creando plata.crm_sales_details'

DROP TABLE IF EXISTS plata.crm_sales_details;

CREATE TABLE plata.crm_sales_details (
    sls_ord_num         VARCHAR(50),
    sls_prd_key         VARCHAR(50),
    sls_cust_id         INTEGER,
    sls_order_dt        DATE,
    sls_ship_dt         DATE,
    sls_due_dt          DATE,
    sls_sales           INTEGER,
    sls_quantity        INTEGER,
    sls_price           INTEGER,
    dwh_create_date     TIMESTAMP DEFAULT LOCALTIMESTAMP
);

-- ============================================================================
-- 5. UBICACIONES ERP
-- ============================================================================

\echo 'Creando plata.erp_loc_a101'

DROP TABLE IF EXISTS plata.erp_loc_a101;

CREATE TABLE plata.erp_loc_a101 (
    cid                 VARCHAR(50),
    cntry               VARCHAR(50),
    dwh_create_date     TIMESTAMP DEFAULT LOCALTIMESTAMP
);

-- ============================================================================
-- 6. INFORMACIÓN DE CLIENTES ERP
-- ============================================================================

\echo 'Creando plata.erp_cust_az12'

DROP TABLE IF EXISTS plata.erp_cust_az12;

CREATE TABLE plata.erp_cust_az12 (
    cid                 VARCHAR(50),
    bdate               DATE,
    gen                 VARCHAR(50),
    dwh_create_date     TIMESTAMP DEFAULT LOCALTIMESTAMP
);

-- ============================================================================
-- 7. CATEGORÍAS DE PRODUCTOS ERP
-- ============================================================================

\echo 'Creando plata.erp_px_cat_g1v2'

DROP TABLE IF EXISTS plata.erp_px_cat_g1v2;

CREATE TABLE plata.erp_px_cat_g1v2 (
    id                  VARCHAR(50),
    cat                 VARCHAR(50),
    subcat              VARCHAR(50),
    maintenance         VARCHAR(50),
    dwh_create_date     TIMESTAMP DEFAULT LOCALTIMESTAMP
);

COMMIT;

\echo '============================================================'
\echo 'FINALIZADO: LAS SEIS TABLAS DE PLATA FUERON CREADAS'
\echo '============================================================'

-- Verificar la columna de auditoría de las seis tablas.

SELECT
    table_schema,
    table_name,
    column_name,
    data_type,
    column_default
FROM information_schema.columns
WHERE table_schema = 'plata'
  AND column_name = 'dwh_create_date'
ORDER BY table_name;