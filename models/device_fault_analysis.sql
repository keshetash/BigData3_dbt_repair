-- Витрина: анализ неисправностей по видам устройств
SELECT
    device_type,
    fault_type,
    COUNT(*)                    AS orders_count,
    ROUND(AVG(repair_cost), 2)  AS avg_repair_cost,
    ROUND(SUM(repair_cost), 2)  AS total_revenue,
    ROUND(AVG(part_cost), 2)    AS avg_part_cost
FROM {{ ref('stg_repair_orders') }}
WHERE validation_status = 'VALID'
GROUP BY device_type, fault_type
ORDER BY device_type, orders_count DESC
