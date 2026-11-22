CREATE VIEW gold.fact_sales AS
SELECT
    -- 1. Identificación y claves de las dimensiones
    sd.sls_ord_num AS order_number,
    pr.product_key,
    cu.customer_key,

    -- 2. Fechas
    sd.sls_order_dt AS order_date,
    sd.sls_ship_dt AS shipping_date,
    sd.sls_due_dt AS due_date,

    -- 3. Cantidades
    sd.sls_sales AS sales_amount,
    sd.sls_quantity AS quantity,
    sd.sls_price AS price

FROM plata.crm_sales_details AS sd

LEFT JOIN gold.dim_products AS pr
    ON sd.sls_prd_key = pr.product_number

LEFT JOIN gold.dim_customers AS cu
    ON sd.sls_cust_id = cu.customer_id;
