-- Витрина: эффективность инженеров по ремонту
SELECT
    engineer_name                                               AS engineer_name,
    COUNT(*)                                                    AS total_orders,
    COUNT(CASE WHEN status = 'Выдан' THEN 1 END)               AS completed_orders,
    COUNT(CASE WHEN status = 'В работе' THEN 1 END)            AS in_progress_orders,
    COUNT(CASE WHEN status = 'Ожидает запчасти' THEN 1 END)    AS waiting_parts_orders,
    ROUND(SUM(repair_cost), 2)                                  AS total_revenue,
    ROUND(AVG(repair_cost), 2)                                  AS avg_repair_cost,
    ROUND(SUM(part_cost), 2)                                    AS total_parts_cost
FROM {{ ref('stg_repair_orders') }}
WHERE validation_status = 'VALID'
GROUP BY engineer_name
ORDER BY total_revenue DESC
