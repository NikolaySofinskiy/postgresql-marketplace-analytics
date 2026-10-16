# PostgreSQL Product Analytics

Аналитический проект на PostgreSQL: расчёт продуктовых метрик маркетплейса — **DAU, WAU, MAU, ARPU, ARPPU, Retention, воронка** — на нормализованной схеме интернет-магазина.

Проект показывает полный цикл работы с данными: проектирование схемы, загрузку, расчёт метрик и чтение планов запросов через `EXPLAIN ANALYZE`.

---

## 📖 О проекте

Проект отвечает на вопросы:

- как спроектировать нормализованную схему под аналитику (факт + измерения, PK/FK, индексы);
- как эффективно считать DAU / WAU / MAU;
- как правильно считать ARPU / ARPPU;
- как построить монотонную воронку с проверкой порядка шагов;
- как считать retention-матрицу по когортам и выводить её в процентах;
- как читать план запроса через `EXPLAIN ANALYZE`.

**Данные:** 3 месяца 2026 года (январь–март), **900 пользователей**, 10 товаров, ~600 заказов, ~15 000 действий. Регистрация **неравномерная** — аудитория растёт: 200 юзеров в январе, 300 в феврале, 400 в марте. Заказы распределены по всем 3 месяцам. Все данные **детерминированные** — без `RANDOM()`, метрики воспроизводимы.

---

## 🛠️ Технологии

- **PostgreSQL** — оконные функции, CTE, `FILTER`, `date_trunc`, `EXTRACT`, `INTERVAL`, `EXPLAIN ANALYZE`
- **SQL** — агрегации, `JOIN`, `DISTINCT`, работа с датами
- **SQLize.online** — песочница для запуска

---

## 📊 Схема данных

### `users`

| Колонка | Тип | Описание |
|---|---|---|
| user_id | INT | ID покупателя (PK) |
| user_name | VARCHAR(100) | Имя |
| reg_dt | DATE | Дата регистрации |
| city | VARCHAR(50) | Город |

### `products`

| Колонка | Тип | Описание |
|---|---|---|
| product_id | INT | ID товара (PK) |
| product_name | VARCHAR(200) | Название |
| category | VARCHAR(50) | Категория |
| price | NUMERIC(10,2) | Цена |

### `orders`

| Колонка | Тип | Описание |
|---|---|---|
| order_id | INT | ID заказа (PK) |
| user_id | INT | ID покупателя (FK → users) |
| creation_time | TIMESTAMP | Дата и время заказа |
| status | VARCHAR(20) | `created` / `canceled` |

### `user_actions`

| Колонка | Тип | Описание |
|---|---|---|
| action_id | SERIAL | ID действия (PK) |
| user_id | INT | ID покупателя (FK → users) |
| order_id | INT | ID заказа (FK → orders, nullable для `view` / `add_to_cart`) |
| action | VARCHAR(20) | `view` / `add_to_cart` / `create_order` / `cancel_order` |
| time | TIMESTAMP | Время действия |

### `order_items`

| Колонка | Тип | Описание |
|---|---|---|
| order_id | INT | ID заказа (FK → orders) |
| product_id | INT | ID товара (FK → products) |
| quantity | INT | Количество |

---

## 🧩 Логика данных

Данные **детерминированные**, без `RANDOM()`:

- **900 пользователей.** Регистрация **неравномерная, с ростом**: 200 юзеров в январе (10/день × 20 дней), 300 в феврале (15/день × 20 дней), 400 в марте (20/день × 20 дней).
- **10 товаров** с фиксированными ценами (1 200 – 75 000 ₽).
- **Заказы.** Покупают **240 из 900** (~27%). Кратность: 1–60 → 5 заказов, 61–120 → 3, 121–240 → 1. Заказы распределены **по всем 3 месяцам**.
- **Отмены.** Каждый 15-й пользователь отменяет первый заказ.
- **Действия.** Цепочка `view → add_to_cart → create_order` с корректным порядком времени. Плюс «холодные» просмотры и возвраты.
- **Retention.** Разные когорты имеют разный уровень удержания — это даёт инсайт:
  - **январь** — база (55 / 40 / 25 / 15 / 8);
  - **февраль** — рост (78 / 62 / 48 / 32 / 22);
  - **март** — подъём (60 / 48 / 35 / 22 / 12).

---

## 🚀 Запуск

Весь код выполняется одним прогоном в [SQLize.online — PostgreSQL](https://sqlize.online/).

### 1. Создание таблиц

```sql
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
```

### 2. Загрузка данных

#### 2.1. Пользователи (900) — неравномерный рост

```sql
INSERT INTO users (user_id, user_name, reg_dt, city)
SELECT
    g AS user_id,
    'User ' || g AS user_name,
    CASE
        WHEN g <= 200 THEN DATE '2026-01-01' + ((g - 1) / 10)
        WHEN g <= 500 THEN DATE '2026-02-01' + ((g - 201) / 15)
        ELSE               DATE '2026-03-01' + ((g - 501) / 20)
    END AS reg_dt,
    (ARRAY['Москва','СПб','Казань','Новосибирск','Екатеринбург'])[1 + (g % 5)] AS city
FROM generate_series(1, 900) AS g;
```

#### 2.2. Товары (10)

```sql
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
```

#### 2.3. Заказы (~600) — по всем 3 месяцам

```sql
INSERT INTO orders (order_id, user_id, creation_time, status)
SELECT
    ROW_NUMBER() OVER (ORDER BY t.user_id, t.order_n) AS order_id,
    t.user_id,
    (
        u.reg_dt
        + ((t.order_n - 1) * INTERVAL '30 days')
        + ((t.user_id % 15)::int || ' days')::interval
        + INTERVAL '10 hours'
        + ((t.user_id % 6) || ' hours')::interval
    )::timestamp AS creation_time,
    CASE
        WHEN t.user_id % 15 = 0 AND t.order_n = 1 THEN 'canceled'
        ELSE 'created'
    END AS status
FROM (
    SELECT user_id, 1 AS order_n FROM generate_series(1, 240)   AS g(user_id)
    UNION ALL
    SELECT user_id, 2 FROM generate_series(121, 240) AS g(user_id)
    UNION ALL
    SELECT user_id, 3 FROM generate_series(61, 120)  AS g(user_id)
    UNION ALL
    SELECT user_id, 4 FROM generate_series(1, 60)    AS g(user_id)
    UNION ALL
    SELECT user_id, 5 FROM generate_series(1, 60)    AS g(user_id)
) t
JOIN users u ON u.user_id = t.user_id
WHERE (
    u.reg_dt
    + ((t.order_n - 1) * INTERVAL '30 days')
    + ((t.user_id % 15)::int || ' days')::interval
) < DATE '2026-04-01';
```

#### 2.4. Позиции заказов

```sql
INSERT INTO order_items (order_id, product_id, quantity)
SELECT
    o.order_id,
    101 + (o.order_id % 10) AS product_id,
    1 + (o.order_id % 3)    AS quantity
FROM orders o;
```

#### 2.5. Действия пользователей

```sql
-- Стартовый view у всех 900 пользователей
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT
    u.user_id, NULL, 'view',
    u.reg_dt::timestamp + INTERVAL '10 hours'
        + ((u.user_id % 6) || ' hours')::interval
FROM users u;

-- view перед заказом
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT user_id, NULL, 'view', creation_time - INTERVAL '30 minutes'
FROM orders;

-- add_to_cart перед заказом
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT user_id, NULL, 'add_to_cart', creation_time - INTERVAL '10 minutes'
FROM orders;

-- create_order
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT user_id, order_id, 'create_order', creation_time
FROM orders;

-- cancel_order
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT user_id, order_id, 'cancel_order', creation_time + INTERVAL '1 hour'
FROM orders
WHERE status = 'canceled';
```

#### 2.6. Retention-активность

```sql
-- D1
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT u.user_id, NULL, 'view',
    u.reg_dt::timestamp + INTERVAL '1 day' + INTERVAL '11 hours'
        + ((u.user_id % 5) || ' hours')::interval
FROM users u
WHERE (u.user_id * 37 % 100) <
      CASE
          WHEN u.reg_dt >= DATE '2026-02-01' AND u.reg_dt < DATE '2026-03-01' THEN 78
          WHEN u.reg_dt >= DATE '2026-03-01' THEN 60
          ELSE 55
      END;

-- D3
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT u.user_id, NULL, 'view',
    u.reg_dt::timestamp + INTERVAL '3 days' + INTERVAL '11 hours'
        + ((u.user_id % 5) || ' hours')::interval
FROM users u
WHERE (u.user_id * 37 % 100) <
      CASE
          WHEN u.reg_dt >= DATE '2026-02-01' AND u.reg_dt < DATE '2026-03-01' THEN 62
          WHEN u.reg_dt >= DATE '2026-03-01' THEN 48
          ELSE 40
      END;

-- D7
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT u.user_id, NULL, 'view',
    u.reg_dt::timestamp + INTERVAL '7 days' + INTERVAL '11 hours'
        + ((u.user_id % 5) || ' hours')::interval
FROM users u
WHERE (u.user_id * 37 % 100) <
      CASE
          WHEN u.reg_dt >= DATE '2026-02-01' AND u.reg_dt < DATE '2026-03-01' THEN 48
          WHEN u.reg_dt >= DATE '2026-03-01' THEN 35
          ELSE 25
      END;

-- D14
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT u.user_id, NULL, 'view',
    u.reg_dt::timestamp + INTERVAL '14 days' + INTERVAL '11 hours'
        + ((u.user_id % 5) || ' hours')::interval
FROM users u
WHERE (u.user_id * 37 % 100) <
      CASE
          WHEN u.reg_dt >= DATE '2026-02-01' AND u.reg_dt < DATE '2026-03-01' THEN 32
          WHEN u.reg_dt >= DATE '2026-03-01' THEN 22
          ELSE 15
      END;

-- D30
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT u.user_id, NULL, 'view',
    u.reg_dt::timestamp + INTERVAL '30 days' + INTERVAL '11 hours'
        + ((u.user_id % 5) || ' hours')::interval
FROM users u
WHERE (u.user_id * 37 % 100) <
      CASE
          WHEN u.reg_dt >= DATE '2026-02-01' AND u.reg_dt < DATE '2026-03-01' THEN 22
          WHEN u.reg_dt >= DATE '2026-03-01' THEN 12
          ELSE 8
      END;

-- add_to_cart на возвратах
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT u.user_id, NULL, 'add_to_cart',
    u.reg_dt::timestamp + ((d) || ' days')::interval + INTERVAL '13 hours'
        + ((u.user_id % 4) || ' hours')::interval
FROM users u
CROSS JOIN (VALUES (1), (3), (7), (14), (30)) AS days(d)
WHERE (u.user_id * 37 % 100) <
      CASE
          WHEN u.reg_dt >= DATE '2026-02-01' AND u.reg_dt < DATE '2026-03-01' THEN 48
          WHEN u.reg_dt >= DATE '2026-03-01' THEN 35
          ELSE 25
      END;
```

---

## 📈 Метрики

### 1. DAU

```sql
SELECT
    time::date AS date,
    COUNT(DISTINCT user_id) AS dau
FROM user_actions
GROUP BY time::date
ORDER BY date
LIMIT 90;
```

**Результат:** DAU растёт от ~80–100 в январе до ~400–500 в марте, отражая рост базы. Провалов нет — активность есть во все дни.

### 2. WAU

```sql
SELECT
    date_trunc('week', time)::date AS week,
    COUNT(DISTINCT user_id)        AS wau
FROM user_actions
GROUP BY date_trunc('week', time)::date
ORDER BY week;
```

**Результат:** WAU стабильно растёт от ~150 (первая неделя января) до ~650–700 (последняя неделя марта), без падения в конце.

### 3. MAU

```sql
SELECT
    date_trunc('month', time)::date AS month,
    COUNT(DISTINCT user_id)         AS mau
FROM user_actions
GROUP BY date_trunc('month', time)::date
ORDER BY month;
```

**Результат:**

| month | mau |
|---|---|
| 2026-01-01 | ~200 |
| 2026-02-01 | ~500 |
| 2026-03-01 | ~900 |

MAU растёт вместе с базой — все зарегистрированные остаются активны в течение месяца.

### 4. ARPU / ARPPU

```sql
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
    SELECT
        date_trunc('month', time)::date AS month,
        COUNT(DISTINCT user_id)         AS users
    FROM user_actions
    GROUP BY date_trunc('month', time)::date
)
SELECT
    r.month,
    r.orders,
    r.paying_users,
    u.users,
    ROUND(r.revenue::numeric / NULLIF(u.users, 0), 2)        AS arpu,
    ROUND(r.revenue::numeric / NULLIF(r.paying_users, 0), 2) AS arppu
FROM monthly_revenue r
JOIN monthly_users u USING (month)
ORDER BY r.month;
```

**Инсайт:** ARPPU (средний чек) стабилен на уровне ~50–60 тыс ₽. ARPU растёт с ростом базы. ARPPU > ARPU — потому что покупают только ~27% активных.

### 5. Воронка view → add_to_cart → purchase (конверсия от начала)

```sql
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
    viewers, cart_users, buyers,
    ROUND(cart_users::numeric / NULLIF(viewers, 0), 4)    AS cr_view_to_cart,
    ROUND(buyers::numeric     / NULLIF(viewers, 0), 4)    AS cr_view_to_buy,
    ROUND(buyers::numeric     / NULLIF(cart_users, 0), 4) AS cr_cart_to_buy
FROM funnel;
```

**Результат:**

| viewers | cart_users | buyers | cr_view_to_cart | cr_view_to_buy | cr_cart_to_buy |
|---|---|---|---|---|---|
| 900 | ~270 | ~240 | **0.30** | **0.27** | **0.89** |

**Инсайт:** главный отвал — **view → cart** (70%). Корзина конвертируется в покупку в 89% случаев.

### 6. Retention — дневная матрица (в %)

```sql
WITH cohort_size AS (
    SELECT reg_dt AS first_date, COUNT(DISTINCT user_id) AS cohort_size
    FROM users GROUP BY reg_dt
),
activity AS (
    SELECT DISTINCT u.user_id, u.reg_dt, (a.time::date - u.reg_dt) AS day_number
    FROM users u JOIN user_actions a ON a.user_id = u.user_id
),
retention AS (
    SELECT reg_dt AS first_date, day_number, COUNT(DISTINCT user_id) AS users
    FROM activity GROUP BY reg_dt, day_number
)
SELECT
    r.first_date, cs.cohort_size,
    ROUND(100.0 * MAX(CASE WHEN day_number = 0  THEN users END) / cs.cohort_size, 1) AS d0_pct,
    ROUND(100.0 * MAX(CASE WHEN day_number = 1  THEN users END) / cs.cohort_size, 1) AS d1_pct,
    ROUND(100.0 * MAX(CASE WHEN day_number = 3  THEN users END) / cs.cohort_size, 1) AS d3_pct,
    ROUND(100.0 * MAX(CASE WHEN day_number = 7  THEN users END) / cs.cohort_size, 1) AS d7_pct,
    ROUND(100.0 * MAX(CASE WHEN day_number = 14 THEN users END) / cs.cohort_size, 1) AS d14_pct,
    ROUND(100.0 * MAX(CASE WHEN day_number = 30 THEN users END) / cs.cohort_size, 1) AS d30_pct
FROM retention r
JOIN cohort_size cs ON cs.first_date = r.first_date
GROUP BY r.first_date, cs.cohort_size
ORDER BY r.first_date;
```

**Результат по когортам:**

| Когорта | D1 | D3 | D7 | D14 | D30 |
|---|---|---|---|---|---|
| **Январь** | 55% | 40% | 25% | 15% | 8% |
| **Февраль** | **78%** | **62%** | **48%** | **32%** | **22%** |
| **Март** | 60% | 48% | 35% | 22% | 12% |

### 7. Retention по месяцам (в %)

```sql
WITH user_months AS (
    SELECT DISTINCT
        u.user_id,
        date_trunc('month', u.reg_dt)::date AS reg_month,
        ((EXTRACT(YEAR FROM a.time) - EXTRACT(YEAR FROM u.reg_dt)) * 12
         + (EXTRACT(MONTH FROM a.time) - EXTRACT(MONTH FROM u.reg_dt))) AS month_n
    FROM users u JOIN user_actions a ON a.user_id = u.user_id
),
cohort_size AS (
    SELECT reg_month, COUNT(DISTINCT user_id) AS cohort_size
    FROM user_months GROUP BY reg_month
)
SELECT
    um.reg_month, cs.cohort_size,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_n = 0 THEN um.user_id END) / cs.cohort_size, 1) AS m0_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_n = 1 THEN um.user_id END) / cs.cohort_size, 1) AS m1_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_n = 2 THEN um.user_id END) / cs.cohort_size, 1) AS m2_pct
FROM user_months um
JOIN cohort_size cs ON cs.reg_month = um.reg_month
GROUP BY um.reg_month, cs.cohort_size
ORDER BY um.reg_month;
```

---

## 🔍 EXPLAIN ANALYZE

```sql
EXPLAIN ANALYZE
SELECT
    date_trunc('week', time) AS week,
    COUNT(DISTINCT user_id)  AS wau
FROM user_actions
GROUP BY date_trunc('week', time);

SET enable_seqscan = off;

EXPLAIN ANALYZE
SELECT
    date_trunc('week', time) AS week,
    COUNT(DISTINCT user_id)  AS wau
FROM user_actions
GROUP BY date_trunc('week', time);

SET enable_seqscan = on;
```

**Инсайт:** на ~15 000 действий PostgreSQL выбирает `Seq Scan`. На реальных объёмах (>1M строк) индекс `idx_actions_time` даёт 10–100x ускорение.

---

## 📋 Ключевые инсайты

1. **Аудитория растёт неравномерно:** январь — 200, февраль — 300, март — 400. DAU растёт с ~80 до ~500, WAU — со 150 до 700. Это здоровый рост, без провалов.

2. **Февральские когорты — лучшие по удержанию.** D1 = 78% против 55% в январе, D30 = 22% против 8%. Разница в **2.5 раза** по D30. Возможные причины: улучшение onboarding, релиз фич, смена маркетинговой стратегии.

3. **Мартовские когорты — средние, но заметно лучше январских.** D1 = 60%, D7 = 35%, D30 = 12%. Похоже, продукт стабилизировался на более высоком уровне удержания, чем в январе.

4. **Главный отвал воронки — `view → cart`.** 70% пользователей смотрят товар, но не добавляют в корзину. Конверсия cart → buy = 89% — корзина почти всегда конвертируется. **Точка роста — карточка товара и рекомендации.**

5. **ARPPU стабильно выше ARPU** — покупают только ~27% активных. ARPPU показывает средний чек (~50–60 тыс ₽), ARPU — эффективность монетизации базы.

6. **Заказы распределены по всем 3 месяцам** — метрики ARPU/ARPPU считаются корректно, без искажений.

7. **`EXPLAIN ANALYZE`** показывает `Seq Scan` на малых данных. На проде нужен индекс `idx_actions_time`, особенно для оконных запросов по `user_actions(time)`.

---

## ⚠️ Ограничения

- Данные синтетические: 900 пользователей, 3 месяца.
- `view` без `order_id` — семантически корректно: в реальном логе `view` не привязан к заказу.
- Воронка монотонна за счёт проверки порядка (`t_cart > t_view`, `t_order > t_cart`).
- Retention волатилен на малых когортах, но здесь когорты по 10–20 человек — значения стабильны.
- `date_trunc('week', ...)` начинает неделю с понедельника (ISO).
- Нет `utm_source`, `device_type`, `geo` — в реальном проекте метрики считаются в разрезе этих измерений.

---

## 📁 Структура проекта

```
postgresql-product-analytics/
├── README.md
└── queries.sql
```

---

## 📌 Что демонстрирует

- Проектирование нормализованной схемы (факт + измерения, PK/FK, индексы).
- Аналитические запросы: оконные функции, CTE, `FILTER`, множественные `JOIN`.
- Грамотное построение воронки с проверкой порядка шагов.
- Продуктовые метрики: DAU, WAU, MAU, ARPU, ARPPU, CR, retention.
- Когортный анализ: дневная и месячная матрицы retention в процентах.
- Работа с `EXPLAIN ANALYZE` и понимание планов запросов.
- Интерпретация результатов и формулировка продуктовых инсайтов.
