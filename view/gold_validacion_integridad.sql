-- validar_integridad_referencial_fact_sales.sql
-- Busca ventas sin correspondencia en las dimensiones
-- de clientes o productos.

SELECT *
FROM gold.fact_sales AS f

LEFT JOIN gold.dim_customers AS c
    ON c.customer_key = f.customer_key

LEFT JOIN gold.dim_products AS p
    ON p.product_key = f.product_key

WHERE c.customer_key IS NULL
   OR p.product_key IS NULL;