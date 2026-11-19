#!/usr/bin/env bash
set -euo pipefail
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
ETAPA="inicio"
trap 'codigo=$?; printf "[ERROR] Etapa: %s | línea: %s | código: %s\n" "$ETAPA" "$LINENO" "$codigo" >&2; exit "$codigo"' ERR
SECONDS=0
cd /workspaces/datawarehouse_consql
CONTENEDOR="postgres-practica"
USUARIO="estudiante"
BASE="practicas_sql"
MODO="${1:-}"
if [[ $# -gt 1 || ( -n "$MODO" && "$MODO" != "--reemplazar" ) ]]; then
    echo "Uso: bash cargar_bronce.sh [--reemplazar]"
    exit 1
fi
ARCHIVOS=(cust_info.csv prd_info.csv sales_details.csv LOC_A101.csv CUST_AZ12.csv PX_CAT_G1V2.csv)
log "=== INICIO DEL FLUJO BRONCE ==="
ETAPA="1/7: comprobar archivos"
log "$ETAPA"
if [[ ! -s 01_bronce.sql ]]; then
    log "ERROR: falta 01_bronce.sql o está vacío."
    exit 1
fi
for archivo in "${ARCHIVOS[@]}"; do
    if [[ ! -s "dataset/$archivo" ]]; then
        log "ERROR: falta dataset/$archivo o está vacío."
        exit 1
    fi
    log "[OK] $archivo: $(wc -c < "dataset/$archivo") bytes."
done
if [[ "$MODO" == "--reemplazar" ]]; then
    log "ADVERTENCIA: se sustituirán los datos de las seis tablas."
    read -r -p "Escribe REEMPLAZAR para continuar: " RESPUESTA
    if [[ "$RESPUESTA" != "REEMPLAZAR" ]]; then
        log "Operación cancelada."
        exit 0
    fi
else
    log "Modo seguro: se cancela la carga si alguna tabla ya tiene datos."
fi
ETAPA="2/7: iniciar el contenedor existente"
log "$ETAPA"
docker start "$CONTENEDOR" >/dev/null
LISTO=false
for intento in {1..30}; do
    if docker exec "$CONTENEDOR" pg_isready -U "$USUARIO" -d postgres >/dev/null 2>&1; then
        LISTO=true
        break
    fi
    log "Esperando a PostgreSQL: intento $intento/30."
    sleep 1
done
if [[ "$LISTO" != true ]]; then
    log "ERROR: PostgreSQL no está listo."
    exit 1
fi
log "[OK] PostgreSQL disponible."
ETAPA="3/7: crear la base si no existe"
log "$ETAPA"
docker exec -i "$CONTENEDOR" \
    psql -X -U "$USUARIO" -d postgres -v ON_ERROR_STOP=1 <<'SQL'
SELECT 'CREATE DATABASE practicas_sql OWNER estudiante'
WHERE NOT EXISTS (
    SELECT 1 FROM pg_database WHERE datname = 'practicas_sql'
)
\gexec
SQL
log "[OK] Base disponible; si ya existía, se ha conservado."
ETAPA="4/7: copiar los CSV"
log "$ETAPA"
docker exec "$CONTENEDOR" mkdir -p /tmp/dataset
for archivo in "${ARCHIVOS[@]}"; do
    log "Copiando $archivo..."
    docker cp "dataset/$archivo" "$CONTENEDOR:/tmp/dataset/$archivo"
    docker exec "$CONTENEDOR" chmod a+r "/tmp/dataset/$archivo"
    origen=$(wc -c < "dataset/$archivo")
    destino=$(docker exec "$CONTENEDOR" sh -c 'wc -c < "$1"' sh "/tmp/dataset/$archivo")
    if [[ "$origen" -ne "$destino" ]]; then
        log "ERROR: tamaños distintos en $archivo."
        exit 1
    fi
    log "[OK] $archivo copiado: $destino bytes."
done
ETAPA="5/7: preparar esquemas, tablas y procedimiento"
log "$ETAPA"
docker exec -i "$CONTENEDOR" \
    psql -X -U "$USUARIO" -d "$BASE" -v ON_ERROR_STOP=1 < 01_bronce.sql
ETAPA="6/7: cargar las seis tablas y medir tiempos"
log "$ETAPA"
if [[ "$MODO" == "--reemplazar" ]]; then
    LLAMADA="CALL bronce.cargar_bronce(TRUE);"
else
    LLAMADA="CALL bronce.cargar_bronce();"
fi
INICIO_LLAMADA=$SECONDS
docker exec "$CONTENEDOR" \
    psql -X -U "$USUARIO" -d "$BASE" -v ON_ERROR_STOP=1 \
    -c "SET client_min_messages = notice;" -c "$LLAMADA"
log "[OK] Carga confirmada. Duración externa de la llamada: $((SECONDS - INICIO_LLAMADA)) segundos (resolución de segundos)."
ETAPA="7/7: consultar registros"
log "$ETAPA"
docker exec -i "$CONTENEDOR" \
    psql -X -U "$USUARIO" -d "$BASE" -v ON_ERROR_STOP=1 <<'SQL'
SELECT 'crm_cust_info' AS tabla, COUNT(*) AS filas FROM bronce.crm_cust_info
UNION ALL
SELECT 'crm_prd_info' AS tabla, COUNT(*) AS filas FROM bronce.crm_prd_info
UNION ALL
SELECT 'crm_sales_details' AS tabla, COUNT(*) AS filas FROM bronce.crm_sales_details
UNION ALL
SELECT 'erp_loc_a101' AS tabla, COUNT(*) AS filas FROM bronce.erp_loc_a101
UNION ALL
SELECT 'erp_cust_az12' AS tabla, COUNT(*) AS filas FROM bronce.erp_cust_az12
UNION ALL
SELECT 'erp_px_cat_g1v2' AS tabla, COUNT(*) AS filas FROM bronce.erp_px_cat_g1v2
ORDER BY tabla;
SQL
log "=== FLUJO COMPLETO: $SECONDS segundos (resolución de segundos) ==="
