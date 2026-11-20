\set ON_ERROR_STOP on
\echo '=== PREPARACIÓN SQL ==='
SET client_min_messages = notice;
CREATE SCHEMA IF NOT EXISTS bronce;
CREATE SCHEMA IF NOT EXISTS plata;
CREATE SCHEMA IF NOT EXISTS oro;
\echo 'Preparando bronce.crm_cust_info (sin modificar tablas existentes)...'
CREATE TABLE IF NOT EXISTS bronce.crm_cust_info (
    cst_id TEXT,
    cst_key TEXT,
    cst_firstname TEXT,
    cst_lastname TEXT,
    cst_marital_status TEXT,
    cst_gndr TEXT,
    cst_create_date TEXT
);
\echo 'Preparando bronce.crm_prd_info (sin modificar tablas existentes)...'
CREATE TABLE IF NOT EXISTS bronce.crm_prd_info (
    prd_id TEXT,
    prd_key TEXT,
    prd_nm TEXT,
    prd_cost TEXT,
    prd_line TEXT,
    prd_start_dt TEXT,
    prd_end_dt TEXT
);
\echo 'Preparando bronce.crm_sales_details (sin modificar tablas existentes)...'
CREATE TABLE IF NOT EXISTS bronce.crm_sales_details (
    sls_ord_num TEXT,
    sls_prd_key TEXT,
    sls_cust_id TEXT,
    sls_order_dt TEXT,
    sls_ship_dt TEXT,
    sls_due_dt TEXT,
    sls_sales TEXT,
    sls_quantity TEXT,
    sls_price TEXT
);
\echo 'Preparando bronce.erp_loc_a101 (sin modificar tablas existentes)...'
CREATE TABLE IF NOT EXISTS bronce.erp_loc_a101 (
    cid TEXT,
    cntry TEXT
);
\echo 'Preparando bronce.erp_cust_az12 (sin modificar tablas existentes)...'
CREATE TABLE IF NOT EXISTS bronce.erp_cust_az12 (
    cid TEXT,
    bdate TEXT,
    gen TEXT
);
\echo 'Preparando bronce.erp_px_cat_g1v2 (sin modificar tablas existentes)...'
CREATE TABLE IF NOT EXISTS bronce.erp_px_cat_g1v2 (
    id TEXT,
    cat TEXT,
    subcat TEXT,
    maintenance TEXT
);

CREATE OR REPLACE PROCEDURE bronce.cargar_bronce(
    p_reemplazar BOOLEAN DEFAULT FALSE
)
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
    v_tiene_datos BOOLEAN;
    v_filas BIGINT;
    v_total BIGINT := 0;
    v_inicio TIMESTAMPTZ := clock_timestamp();
    v_inicio_tabla TIMESTAMPTZ;
    v_fin_tabla TIMESTAMPTZ;
    v_segundos NUMERIC;
    v_suma_segundos NUMERIC := 0;
    v_tabla_actual TEXT := 'preparación';
    v_resumen TEXT[] := ARRAY[]::TEXT[];
    v_linea TEXT;
BEGIN
    RAISE NOTICE '=== INICIO DE CARGA: % ===', v_inicio;
    RAISE NOTICE 'Modo reemplazo: %', p_reemplazar;
    RAISE NOTICE 'Esperando bloqueo para ejecutar la carga...';
    PERFORM pg_advisory_xact_lock(803421);
    LOCK TABLE
        bronce.crm_cust_info,
        bronce.crm_prd_info,
        bronce.crm_sales_details,
        bronce.erp_loc_a101,
        bronce.erp_cust_az12,
        bronce.erp_px_cat_g1v2
    IN ACCESS EXCLUSIVE MODE;
    RAISE NOTICE '[OK] Bloqueos obtenidos.';

    IF p_reemplazar THEN
        RAISE NOTICE 'Vaciando las seis tablas dentro de la transacción...';
        TRUNCATE TABLE
        bronce.crm_cust_info,
        bronce.crm_prd_info,
        bronce.crm_sales_details,
        bronce.erp_loc_a101,
        bronce.erp_cust_az12,
        bronce.erp_px_cat_g1v2;
    ELSE
        RAISE NOTICE 'Comprobando que las seis tablas estén vacías...';
        SELECT EXISTS (SELECT 1 FROM bronce.crm_cust_info)
            OR EXISTS (SELECT 1 FROM bronce.crm_prd_info)
            OR EXISTS (SELECT 1 FROM bronce.crm_sales_details)
            OR EXISTS (SELECT 1 FROM bronce.erp_loc_a101)
            OR EXISTS (SELECT 1 FROM bronce.erp_cust_az12)
            OR EXISTS (SELECT 1 FROM bronce.erp_px_cat_g1v2) INTO v_tiene_datos;
        IF v_tiene_datos THEN
            RAISE EXCEPTION
                'Alguna tabla ya tiene datos. Para sustituir las seis cargas, '
                'ejecute el script Bash con --reemplazar.';
        END IF;
    END IF;

    FOR r IN
        SELECT * FROM (
            VALUES
            (1, 'crm_cust_info', 'cust_info.csv', 'cst_id, cst_key, cst_firstname, cst_lastname, cst_marital_status, cst_gndr, cst_create_date'),
            (2, 'crm_prd_info', 'prd_info.csv', 'prd_id, prd_key, prd_nm, prd_cost, prd_line, prd_start_dt, prd_end_dt'),
            (3, 'crm_sales_details', 'sales_details.csv', 'sls_ord_num, sls_prd_key, sls_cust_id, sls_order_dt, sls_ship_dt, sls_due_dt, sls_sales, sls_quantity, sls_price'),
            (4, 'erp_loc_a101', 'LOC_A101.csv', 'cid, cntry'),
            (5, 'erp_cust_az12', 'CUST_AZ12.csv', 'cid, bdate, gen'),
            (6, 'erp_px_cat_g1v2', 'PX_CAT_G1V2.csv', 'id, cat, subcat, maintenance')
        ) AS archivos(orden, tabla, archivo, columnas)
        ORDER BY orden
    LOOP
        v_tabla_actual := r.tabla;
        RAISE NOTICE '[%/6] Iniciando bronce.% desde /tmp/dataset/%',
            r.orden, r.tabla, r.archivo;

        v_inicio_tabla := clock_timestamp();
        EXECUTE format(
            'COPY bronce.%I (%s) FROM %L '
            'WITH (FORMAT csv, HEADER true, DELIMITER '','', ENCODING ''UTF8'')',
            r.tabla, r.columnas, '/tmp/dataset/' || r.archivo
        );
        GET DIAGNOSTICS v_filas = ROW_COUNT;
        v_fin_tabla := clock_timestamp();

        v_segundos := EXTRACT(EPOCH FROM (v_fin_tabla - v_inicio_tabla));
        v_suma_segundos := v_suma_segundos + v_segundos;
        v_total := v_total + v_filas;
        RAISE NOTICE '[OK] bronce.% | filas: % | inicio: % | fin: %',
            r.tabla, v_filas, v_inicio_tabla, v_fin_tabla;
        RAISE NOTICE 'Tiempo de carga: % segundos (% milisegundos)',
            round(v_segundos, 3), round(v_segundos * 1000, 3);

        v_resumen := array_append(v_resumen, format(
            '%s | %s filas | %s s | %s ms',
            'bronce.' || r.tabla, v_filas,
            round(v_segundos, 3), round(v_segundos * 1000, 3)
        ));
    END LOOP;

    RAISE NOTICE '=== RESUMEN DE TIEMPOS POR TABLA ===';
    FOREACH v_linea IN ARRAY v_resumen LOOP
        RAISE NOTICE '%', v_linea;
    END LOOP;
    RAISE NOTICE 'Total de filas: %', v_total;
    RAISE NOTICE 'Suma de tiempos de carga de las seis tablas: % segundos',
        round(v_suma_segundos, 3);
    RAISE NOTICE 'Tiempo del procedimiento, antes de confirmar: % segundos',
        round(EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)), 3);
    RAISE NOTICE '=== FIN DEL PROCEDIMIENTO ===';
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Error en etapa/tabla: % | SQLSTATE: % | %',
        v_tabla_actual, SQLSTATE, SQLERRM;
    RAISE WARNING 'Tiempo hasta el error: % segundos',
        round(EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)), 3);
    RAISE WARNING 'Se revierten los cambios de esta llamada, incluido el vaciado.';
    RAISE;
END;
$$;
\echo '[OK] Esquemas, tablas y procedimiento disponibles.'
