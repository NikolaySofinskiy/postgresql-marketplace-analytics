-- 5. АНАЛИТИЧЕСКИЕ ЗАПРОСЫ

-- 5.1. GMV, количество заказов и покупателей
SELECT
    SUM(revenue)              AS gmv,
    COUNT(DISTINCT order_id)  AS orders_count,
    COUNT(DISTINCT user_id)   AS buyers_count
FROM orders;

-- 5.2. Топ продавцов по выручке (с городом)
SELECT
    s.seller_id,
    s.seller_name,
    c.city_name,
    SUM(o.revenue)              AS total_revenue,
    COUNT(DISTINCT o.order_id)  AS orders_cnt,
    ROUND(AVG(o.revenue), 2)    AS avg_order_value
FROM orders o
JOIN sellers s ON o.seller_id = s.seller_id
JOIN cities  c ON s.city_id   = c.city_id
GROUP BY s.seller_id, s.seller_name, c.city_name
ORDER BY total_revenue DESC
LIMIT 5;

-- 5.3. Выручка по регионам доставки
SELECT
    region,
    SUM(revenue)              AS revenue,
    COUNT(DISTINCT order_id)  AS orders_cnt,
    COUNT(DISTINCT user_id)   AS buyers
FROM orders
GROUP BY region
ORDER BY revenue DESC;

-- 5.4. Динамика GMV по дням с накопительным итогом
SELECT
    order_dt,
    SUM(revenue) AS daily_gmv,
    COUNT(DISTINCT order_id) AS daily_orders,
    SUM(SUM(revenue)) OVER (ORDER BY order_dt) AS cumulative_gmv
FROM orders
GROUP BY order_dt
ORDER BY order_dt;

-- 5.5. Retention покупателей (активные дни, с городом)
SELECT
    u.user_id,
    u.user_name,
    c.city_name,
    COUNT(DISTINCT o.order_dt) AS active_days,
    MIN(o.order_dt)            AS first_order,
    MAX(o.order_dt)            AS last_order,
    SUM(o.revenue)             AS lifetime_revenue
FROM orders o
JOIN users  u ON o.user_id = u.user_id
JOIN cities c ON u.city_id = c.city_id
GROUP BY u.user_id, u.user_name, c.city_name
HAVING COUNT(DISTINCT o.order_dt) > 1
ORDER BY active_days DESC, lifetime_revenue DESC;

-- 5.6. Средний чек по регионам доставки
SELECT
    region,
    ROUND(SUM(revenue) / COUNT(DISTINCT order_id), 2) AS avg_order_value,
    ROUND(AVG(revenue), 2) AS avg_line_value
FROM orders
GROUP BY region
ORDER BY avg_order_value DESC;

-- 5.7. Разбивка заказов по регионам доставки через FILTER
SELECT
    s.seller_id,
    s.seller_name,
    COUNT(*) FILTER (WHERE o.region = 'Москва') AS orders_msk,
    COUNT(*) FILTER (WHERE o.region = 'СПб')    AS orders_spb,
    COUNT(*) FILTER (WHERE o.region NOT IN ('Москва', 'СПб')) AS orders_other
FROM orders o
JOIN sellers s ON o.seller_id = s.seller_id
GROUP BY s.seller_id, s.seller_name
ORDER BY s.seller_id;

-- 5.8. Ранжирование продавцов внутри категорий товаров
WITH seller_revenue AS (
    SELECT
        p.category,
        s.seller_id,
        s.seller_name,
        c.city_name,
        SUM(o.revenue) AS total_revenue
    FROM orders o
    JOIN sellers  s ON o.seller_id  = s.seller_id
    JOIN products p ON o.product_id = p.product_id
    JOIN cities   c ON s.city_id    = c.city_id
    GROUP BY p.category, s.seller_id, s.seller_name, c.city_name
)
SELECT
    category,
    seller_id,
    seller_name,
    city_name,
    total_revenue,
    RANK() OVER (PARTITION BY category ORDER BY total_revenue DESC) AS rank_in_category
FROM seller_revenue
ORDER BY category, rank_in_category;

-- 5.9. Топ товаров по выручке
SELECT
    p.product_id,
    p.product_name,
    p.category,
    SUM(o.quantity)  AS total_qty,
    SUM(o.revenue)   AS total_revenue
FROM orders o
JOIN products p ON o.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY total_revenue DESC
LIMIT 5;

-- 5.10. География: покупатели и продавцы по городам
SELECT
    c.city_id,
    c.city_name,
    COUNT(DISTINCT s.seller_id) AS sellers_cnt,
    COUNT(DISTINCT u.user_id)   AS buyers_cnt
FROM cities c
LEFT JOIN sellers s ON s.city_id = c.city_id
LEFT JOIN users   u ON u.city_id = c.city_id
GROUP BY c.city_id, c.city_name
ORDER BY sellers_cnt DESC, buyers_cnt DESC;

-- 5.11. Продавцы и их покупатели из одного города
SELECT
    s.seller_id,
    s.seller_name,
    c.city_name,
    COUNT(DISTINCT o.user_id) AS buyers_from_same_city
FROM orders o
JOIN sellers s ON o.seller_id = s.seller_id
JOIN users   u ON o.user_id   = u.user_id
JOIN cities  c ON s.city_id   = c.city_id
WHERE s.city_id = u.city_id
GROUP BY s.seller_id, s.seller_name, c.city_name
ORDER BY buyers_from_same_city DESC;

-- 5.12. Оптимизация: EXPLAIN ANALYZE
EXPLAIN ANALYZE
SELECT region, SUM(revenue)
FROM orders
WHERE order_dt >= DATE '2026-10-05'
GROUP BY region;