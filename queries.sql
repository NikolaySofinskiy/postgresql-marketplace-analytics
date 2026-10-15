-- 1. Создание таблиц
CREATE TABLE users (
    user_id    INT PRIMARY KEY,
    user_name  VARCHAR(100) NOT NULL,
    reg_dt     DATE NOT NULL,
    city       VARCHAR(50) NOT NULL
);

CREATE TABLE products (
    product_id   INT PRIMARY KEY,
    product_name VARCHAR(200) NOT NULL,
    category     VARCHAR(50) NOT NULL,
    price        NUMERIC(10,2) NOT NULL
);

CREATE TABLE orders (
    order_id      INT PRIMARY KEY,
    user_id       INT NOT NULL REFERENCES users(user_id),
    creation_time TIMESTAMP NOT NULL,
    status        VARCHAR(20) NOT NULL
);

CREATE TABLE user_actions (
    action_id  SERIAL PRIMARY KEY,
    user_id    INT NOT NULL REFERENCES users(user_id),
    order_id   INT REFERENCES orders(order_id),
    action     VARCHAR(20) NOT NULL,
    time       TIMESTAMP NOT NULL
);

CREATE TABLE order_items (
    order_id   INT NOT NULL REFERENCES orders(order_id),
    product_id INT NOT NULL REFERENCES products(product_id),
    quantity   INT NOT NULL DEFAULT 1,
    PRIMARY KEY (order_id, product_id)
);

CREATE INDEX idx_actions_time ON user_actions(time);
CREATE INDEX idx_actions_user ON user_actions(user_id);
CREATE INDEX idx_orders_time  ON orders(creation_time);
CREATE INDEX idx_orders_user  ON orders(user_id);

-- 2. Загрузка данных
-- 2.1. Пользователи (100)
INSERT INTO users (user_id, user_name, reg_dt, city)
SELECT
    g AS user_id,
    'User ' || g AS user_name,
    DATE '2026-01-01' + ((g - 1) % 90) AS reg_dt,
    (ARRAY['Москва','СПб','Казань','Новосибирск','Екатеринбург'])[1 + (g % 5)] AS city
FROM generate_series(1, 100) AS g;

-- 2.2. Товары
INSERT INTO products (product_id, product_name, category, price) VALUES
(101, 'Смартфон X',        'Электроника',   45000),
(102, 'Наушники Y',        'Электроника',    8000),
(103, 'Книга "Аналитика"', 'Книги',           1200),
(104, 'Кофемашина Z',      'Дом',            35000),
(105, 'Беговая дорожка',   'Спорт',          60000),
(106, 'Конструктор',       'Детские товары',  2500),
(107, 'Ноутбук Pro',       'Электроника',    75000),
(108, 'Кресло офисное',    'Дом',            18000),
(109, 'Книга "SQL"',       'Книги',           1500),
(110, 'Мяч футбольный',    'Спорт',           2500);

-- 2.3. Заказы (~220)
INSERT INTO orders (order_id, user_id, creation_time, status)
SELECT
    ROW_NUMBER() OVER (ORDER BY user_id, order_n) + 1000 AS order_id,
    user_id,
    DATE '2026-01-01' + ((user_id * 3 + order_n * 20) % 90)::int
        + INTERVAL '8 hours' + (user_id % 8) * INTERVAL '1 hour' AS creation_time,
    CASE WHEN user_id % 12 = 0 AND order_n = 1 THEN 'canceled' ELSE 'created' END AS status
FROM (
    -- Юзеры 1–3: 5 заказов
    SELECT u.user_id, n AS order_n
    FROM users u
    CROSS JOIN generate_series(1, 5) AS n
    WHERE u.user_id <= 3

    UNION ALL

    -- Юзеры 4–13: 3 заказа
    SELECT u.user_id, n AS order_n
    FROM users u
    CROSS JOIN generate_series(1, 3) AS n
    WHERE u.user_id BETWEEN 4 AND 13

    UNION ALL

    -- Юзеры 14–33: 2 заказа
    SELECT u.user_id, n AS order_n
    FROM users u
    CROSS JOIN generate_series(1, 2) AS n
    WHERE u.user_id BETWEEN 14 AND 33

    UNION ALL

    -- Юзеры 34–80: 1 заказ
    SELECT u.user_id, 1 AS order_n
    FROM users u
    WHERE u.user_id BETWEEN 34 AND 80
) t;

-- 2.4. Позиции заказов
INSERT INTO order_items (order_id, product_id, quantity)
SELECT
    o.order_id,
    101 + (o.order_id % 10) AS product_id,
    1 + (o.order_id % 3)    AS quantity
FROM orders o;

-- 2.5. Действия пользователей — цепочка событий
-- 1. view перед заказом (за 30 минут до создания)
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT user_id, NULL, 'view', creation_time - INTERVAL '30 minutes'
FROM orders;

-- 2. add_to_cart перед заказом (за 10 минут до создания)
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT user_id, NULL, 'add_to_cart', creation_time - INTERVAL '10 minutes'
FROM orders;

-- 3. create_order — по всем заказам
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT user_id, order_id, 'create_order', creation_time
FROM orders;

-- 4. cancel_order — по отменённым
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT user_id, order_id, 'cancel_order', creation_time + INTERVAL '1 hour'
FROM orders
WHERE status = 'canceled';

-- 5. Дополнительные view без заказа (для реалистичного CR)
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT
    u.user_id,
    NULL,
    'view',
    d.day::timestamp + INTERVAL '12 hours' + (u.user_id % 8) * INTERVAL '1 hour'
FROM users u
CROSS JOIN generate_series(DATE '2026-01-01', DATE '2026-03-31', INTERVAL '1 day') AS d(day)
WHERE u.user_id <= 60
  AND (u.user_id + EXTRACT(DAY FROM d.day)::int) % 3 <> 0;

-- 6. Дополнительные add_to_cart без заказа (25% от доп. view, для реалистичного CR view → cart)
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT
    u.user_id,
    NULL,
    'add_to_cart',
    d.day::timestamp + INTERVAL '13 hours' + (u.user_id % 8) * INTERVAL '1 hour'
FROM users u
CROSS JOIN generate_series(DATE '2026-01-01', DATE '2026-03-31', INTERVAL '1 day') AS d(day)
WHERE u.user_id <= 60
  AND u.user_id % 4 = 0
  AND (u.user_id + EXTRACT(DAY FROM d.day)::int) % 3 <> 0;

-- 3. Метрики и результаты
-- 3.1 DAU
SELECT
    time::date AS date,
    COUNT(DISTINCT user_id) AS dau
FROM user_actions
GROUP BY time::date
ORDER BY date
LIMIT 30;

-- 3.2 WAU
SELECT
    date_trunc('week', time) AS week,
    COUNT(DISTINCT user_id)  AS wau
FROM user_actions
GROUP BY date_trunc('week', time)
ORDER BY week;

-- 3.3 MAU
SELECT
    date_trunc('month', time)::date AS month,
    COUNT(DISTINCT user_id)         AS mau
FROM user_actions
GROUP BY date_trunc('month', time)
ORDER BY month;

-- 3.4 ARPU / ARPPU
WITH daily_revenue AS (
    SELECT
        o.creation_time::date AS date,
        COUNT(DISTINCT o.order_id) AS orders,
        COUNT(DISTINCT o.user_id)  AS paying_users,
        SUM(p.price * oi.quantity) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN products p     ON p.product_id = oi.product_id
    WHERE o.status = 'created'
    GROUP BY o.creation_time::date
),
daily_users AS (
    SELECT time::date AS date, COUNT(DISTINCT user_id) AS users
    FROM user_actions
    GROUP BY time::date
)
SELECT
    r.date,
    r.orders,
    r.paying_users,
    ROUND(r.revenue::decimal / NULLIF(u.users, 0), 2)         AS arpu,
    ROUND(r.revenue::decimal / NULLIF(r.paying_users, 0), 2)  AS arppu
FROM daily_revenue r
LEFT JOIN daily_users u USING (date)
ORDER BY r.date
LIMIT 20;

-- 3.5 ARPU / ARPPU по месяцам
WITH monthly_revenue AS (
    SELECT
        date_trunc('month', o.creation_time)::date AS month,
        COUNT(DISTINCT o.order_id) AS orders,
        COUNT(DISTINCT o.user_id)  AS paying_users,
        SUM(p.price * oi.quantity) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN products p     ON p.product_id = oi.product_id
    WHERE o.status = 'created'
    GROUP BY date_trunc('month', o.creation_time)::date
),
monthly_users AS (
    SELECT date_trunc('month', time)::date AS month, COUNT(DISTINCT user_id) AS users
    FROM user_actions
    GROUP BY date_trunc('month', time)::date
)
SELECT
    r.month,
    r.orders,
    r.paying_users,
    u.users,
    ROUND(r.revenue::decimal / NULLIF(u.users, 0), 2)         AS arpu,
    ROUND(r.revenue::decimal / NULLIF(r.paying_users, 0), 2)  AS arppu
FROM monthly_revenue r
JOIN monthly_users u USING (month)
ORDER BY r.month;

-- 3.6 CR — Conversion Rate (view → purchase)
WITH daily_views AS (
    SELECT time::date AS date, COUNT(DISTINCT user_id) AS viewers
    FROM user_actions
    WHERE action = 'view'
    GROUP BY time::date
),
daily_buyers AS (
    SELECT
        time::date AS date,
        COUNT(DISTINCT user_id) AS buyers
    FROM user_actions
    WHERE action = 'create_order'
      AND order_id NOT IN (
          SELECT order_id FROM user_actions WHERE action = 'cancel_order'
      )
    GROUP BY time::date
)
SELECT
    v.date,
    v.viewers,
    COALESCE(b.buyers, 0) AS buyers,
    ROUND(COALESCE(b.buyers, 0)::decimal / NULLIF(v.viewers, 0), 4) AS cr
FROM daily_views v
LEFT JOIN daily_buyers b USING (date)
ORDER BY v.date
LIMIT 20;

-- 3.7 Воронка view → add_to_cart → purchase
WITH user_steps AS (
    SELECT
        user_id,
        MIN(CASE WHEN action = 'view'         THEN time END) AS t_view,
        MIN(CASE WHEN action = 'add_to_cart'  THEN time END) AS t_cart,
        MIN(CASE WHEN action = 'create_order' THEN time END) AS t_order
    FROM user_actions
    GROUP BY user_id
),
funnel AS (
    SELECT
        COUNT(*) FILTER (WHERE t_view IS NOT NULL) AS viewers,
        COUNT(*) FILTER (WHERE t_view IS NOT NULL
                           AND t_cart IS NOT NULL
                           AND t_cart > t_view)    AS cart_users,
        COUNT(*) FILTER (WHERE t_view IS NOT NULL
                           AND t_cart IS NOT NULL
                           AND t_cart > t_view
                           AND t_order IS NOT NULL
                           AND t_order > t_cart)   AS buyers
    FROM user_steps
)
SELECT
    viewers,
    cart_users,
    buyers,
    ROUND(cart_users::decimal / NULLIF(viewers, 0), 4)   AS cr_view_to_cart,
    ROUND(buyers::decimal    / NULLIF(cart_users, 0), 4) AS cr_cart_to_buy,
    ROUND(buyers::decimal    / NULLIF(viewers, 0), 4)    AS cr_view_to_buy
FROM funnel;

-- 3.8 Retention — дневная матрица
WITH cohort AS (
    SELECT
        start_date,
        time::date AS date,
        COUNT(DISTINCT user_id) AS users
    FROM (
        SELECT
            user_id,
            time::date,
            MIN(time::date) OVER (PARTITION BY user_id) AS start_date
        FROM user_actions
    ) t1
    GROUP BY start_date, time::date
),
cohort_size AS (
    SELECT start_date, users AS cohort_size
    FROM cohort
    WHERE date = start_date
),
retention AS (
    SELECT
        start_date,
        date - start_date AS day_number,
        ROUND(
            users::decimal / MAX(users) OVER (PARTITION BY start_date),
            2
        ) AS retention
    FROM cohort
)
SELECT
    date_trunc('month', r.start_date)::date AS start_month,
    r.start_date,
    cs.cohort_size,
    COALESCE(MAX(CASE WHEN day_number = 0  THEN retention END), 1.00) AS "0",
    MAX(CASE WHEN day_number = 1  THEN retention END) AS "1",
    MAX(CASE WHEN day_number = 3  THEN retention END) AS "3",
    MAX(CASE WHEN day_number = 7  THEN retention END) AS "7",
    MAX(CASE WHEN day_number = 14 THEN retention END) AS "14",
    MAX(CASE WHEN day_number = 30 THEN retention END) AS "30"
FROM retention r
JOIN cohort_size cs ON cs.start_date = r.start_date
GROUP BY date_trunc('month', r.start_date)::date, r.start_date, cs.cohort_size
ORDER BY r.start_date
LIMIT 20;

-- 3.9 Retention по когортам регистрации (месяцы)
WITH user_months AS (
    SELECT DISTINCT
        u.user_id,
        date_trunc('month', u.reg_dt)::date AS reg_month,
        (
            (EXTRACT(YEAR  FROM a.time) - EXTRACT(YEAR  FROM u.reg_dt)) * 12
          + (EXTRACT(MONTH FROM a.time) - EXTRACT(MONTH FROM u.reg_dt))
        ) AS month_n
    FROM users u
    JOIN user_actions a ON a.user_id = u.user_id
),
cohort_size AS (
    SELECT reg_month, COUNT(DISTINCT user_id) AS cohort_size
    FROM user_months
    GROUP BY reg_month
)
SELECT
    um.reg_month,
    cs.cohort_size,
    COUNT(DISTINCT CASE WHEN month_n = 0 THEN um.user_id END) AS m0,
    COUNT(DISTINCT CASE WHEN month_n = 1 THEN um.user_id END) AS m1,
    COUNT(DISTINCT CASE WHEN month_n = 2 THEN um.user_id END) AS m2
FROM user_months um
JOIN cohort_size cs ON cs.reg_month = um.reg_month
GROUP BY um.reg_month, cs.cohort_size
ORDER BY um.reg_month;

-- 3.10 Топ-10 пользователей по выручке
SELECT
    u.user_id,
    u.user_name,
    COUNT(DISTINCT o.order_id) AS orders,
    SUM(p.price * oi.quantity) AS revenue
FROM users u
JOIN orders o       ON o.user_id = u.user_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p     ON p.product_id = oi.product_id
WHERE o.status = 'created'
GROUP BY u.user_id, u.user_name
ORDER BY revenue DESC
LIMIT 10;

-- 4. EXPLAIN ANALYZE
EXPLAIN ANALYZE
SELECT
    date_trunc('week', time) AS week,
    COUNT(DISTINCT user_id)  AS wau
FROM user_actions
GROUP BY date_trunc('week', time);

-- 5. Проверка, что индекс работает:
SET enable_seqscan = off;
EXPLAIN ANALYZE
SELECT date_trunc('week', time) AS week, COUNT(DISTINCT user_id) AS wau
FROM user_actions
GROUP BY date_trunc('week', time);
SET enable_seqscan = on;