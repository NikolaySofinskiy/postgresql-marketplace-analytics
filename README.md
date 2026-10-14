# PostgreSQL Marketplace Analytics

Аналитический проект на PostgreSQL: расчёт продуктовых метрик маркетплейса (DAU, WAU, MAU, ARPU, ARPPU, CR, Retention) на реляционной схеме с индексами и воспроизводимой генерацией синтетических данных.

## 📖 О проекте

Проект показывает полный цикл работы с PostgreSQL: проектирование схемы, генерацию данных и расчёт продуктовых метрик. Цель — продемонстрировать навыки работы с PostgreSQL и понимание продуктовых метрик маркетплейса.

Проект отвечает на вопросы: как спроектировать нормализованную схему под аналитику маркетплейса, как эффективно считать DAU/WAU/MAU, как использовать оконные функции для retention-матрицы. В качестве примера используется маркетплейс: заказы, покупатели, товары и действия пользователей.

Данные генерируются с фиксированным seed через `setseed()`, поэтому при каждом запуске скрипта получается один и тот же набор строк — метрики воспроизводимы.

## 🛠️ Технологии

- **PostgreSQL** — оконные функции, CTE, `FILTER`, индексы, `generate_series`, `date_trunc`, `setseed`, `EXPLAIN ANALYZE`
- **SQL** — агрегации, JOIN, работа с датами и интервалами
- **SQLize.online** — онлайн-песочница для запуска

## 📊 Схема данных

Пять таблиц: `orders` (факт), `order_items` (детализация), `users`, `products` (измерения), `user_actions` (лог действий).

### Таблица `users`

| Колонка   | Тип          | Описание              |
|-----------|--------------|-----------------------|
| user_id   | INT          | ID покупателя (PK)    |
| user_name | VARCHAR(100) | Имя                   |
| reg_dt    | DATE         | Дата регистрации      |
| city      | VARCHAR(50)  | Город                 |

### Таблица `products`

| Колонка      | Тип           | Описание          |
|--------------|---------------|-------------------|
| product_id   | INT           | ID товара (PK)    |
| product_name | VARCHAR(200)  | Название          |
| category     | VARCHAR(50)   | Категория         |
| price        | NUMERIC(10,2) | Цена              |

### Таблица `orders`

| Колонка       | Тип          | Описание                |
|---------------|--------------|-------------------------|
| order_id      | INT          | ID заказа (PK)          |
| user_id       | INT          | ID покупателя (FK)      |
| creation_time | TIMESTAMP    | Дата и время заказа     |
| status        | VARCHAR(20)  | `created` / `canceled`  |

### Таблица `user_actions`

| Колонка   | Тип         | Описание                          |
|-----------|-------------|-----------------------------------|
| action_id | SERIAL      | ID действия (PK)                  |
| user_id   | INT         | ID покупателя (FK)                |
| order_id  | INT         | ID заказа (FK, nullable)          |
| action    | VARCHAR(20) | `create_order` / `cancel_order`   |
| time      | TIMESTAMP   | Время действия                    |

### Таблица `order_items`

| Колонка    | Тип | Описание        |
|------------|-----|-----------------|
| order_id   | INT | ID заказа (FK)  |
| product_id | INT | ID товара (FK)  |
| quantity   | INT | Количество      |

> **О данных:** Набор данных синтетический и создан исключительно для демонстрации возможностей PostgreSQL. Все `user_id`, названия и временные метки сгенерированы. Проект не использует реальные логи, персональные данные или коммерческую информацию.

## 🚀 Запуск проекта

Все шаги выполняются в [SQLize.online — PostgreSQL](https://sqlize.online/sql/psql/).

> ⚠️ **Важно:** SQLize.online не сохраняет состояние между отдельными запусками. Каждый `Run` создаёт новую временную базу данных. Поэтому весь код ниже нужно выполнить за один запуск, а не по частям.

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

### 2. Генерация данных

> Перед вставкой выставляем seed через `setseed(0.42)`. Один и тот же seed даёт одну и ту же последовательность значений `random()` — данные будут воспроизводимы при каждом запуске.

```sql
-- Фиксируем seed, чтобы random() давал воспроизводимую последовательность
SELECT setseed(0.42);

-- Пользователи
INSERT INTO users (user_id, user_name, reg_dt, city)
SELECT
    g AS user_id,
    'User_' || g,
    DATE '2024-01-01' + (random() * 180)::int,
    (ARRAY['Москва','СПб','Казань','Новосибирск','Екатеринбург'])[1 + (random()*4)::int]
FROM generate_series(1, 300) AS g;

-- Товары
INSERT INTO products (product_id, product_name, category, price)
SELECT
    g,
    'Product_' || g,
    (ARRAY['Электроника','Книги','Дом','Спорт','Детское'])[1 + (random()*4)::int],
    (ARRAY[500, 1200, 2500, 8000, 15000, 35000, 45000, 60000])[1 + (random()*7)::int]
FROM generate_series(1, 50) AS g;

-- Заказы: creation_time считается от reg_dt пользователя,
-- поэтому все 3000 заказов гарантированно вставятся.
WITH raw AS (
    SELECT
        g AS order_id,
        1 + (random() * 299)::int AS user_id,
        (random() < 0.10) AS is_canceled
    FROM generate_series(1, 3000) AS g
)
INSERT INTO orders (order_id, user_id, creation_time, status)
SELECT
    r.order_id,
    r.user_id,
    u.reg_dt::timestamp
        + (random() * 180)::int * INTERVAL '1 day'
        + (random() * 86400)::int * INTERVAL '1 second' AS creation_time,
    CASE WHEN r.is_canceled THEN 'canceled' ELSE 'created' END
FROM raw r
JOIN users u ON u.user_id = r.user_id;

-- Действия: create_order
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT user_id, order_id, 'create_order', creation_time
FROM orders;

-- Действия: cancel_order
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT user_id, order_id, 'cancel_order', creation_time + INTERVAL '1 hour'
FROM orders
WHERE status = 'canceled';

-- Позиции заказов: без дублей product_id внутри заказа
INSERT INTO order_items (order_id, product_id, quantity)
SELECT DISTINCT
    o.order_id,
    1 + (random() * 49)::int AS product_id,
    1 + (random() * 2)::int AS quantity
FROM orders o
CROSS JOIN generate_series(1, 3) AS g
ON CONFLICT DO NOTHING;
```

> **Проверка воспроизводимости.** Выполните скрипт дважды и сравните:
> ```sql
> SELECT COUNT(*), SUM(revenue) FROM (
>     SELECT o.order_id, SUM(p.price * oi.quantity) AS revenue
>     FROM orders o
>     JOIN order_items oi ON oi.order_id = o.order_id
>     JOIN products p ON p.product_id = oi.product_id
>     GROUP BY o.order_id
> ) t;
> ```
> Числа должны совпасть.

---

## 📈 Метрики

### 1. DAU

```sql
SELECT
    time::date AS date,
    COUNT(DISTINCT user_id) AS dau
FROM user_actions
GROUP BY time::date
ORDER BY date;
```

> **Бизнес-смысл:** базовая метрика вовлечённости. Показывает, сколько уникальных пользователей заходят в продукт каждый день.

### 2. WAU — по календарным неделям

```sql
SELECT
    date_trunc('week', time) AS week,
    COUNT(DISTINCT user_id)  AS wau
FROM user_actions
GROUP BY date_trunc('week', time)
ORDER BY week;
```

С числом активных дней (видно неполные недели):

```sql
SELECT
    date_trunc('week', time)::date AS week,
    COUNT(DISTINCT user_id)        AS wau,
    COUNT(DISTINCT time::date)     AS active_days
FROM user_actions
GROUP BY date_trunc('week', time)
ORDER BY week;
```

> **Бизнес-смысл:** `date_trunc('week', ...)` в PostgreSQL начинает неделю с понедельника (ISO 8601). Если `active_days < 7` — неделя неполная, WAU на ней занижен.

### 3. MAU — по календарным месяцам

```sql
SELECT
    date_trunc('month', time)::date AS month,
    COUNT(DISTINCT user_id)         AS mau
FROM user_actions
GROUP BY date_trunc('month', time)
ORDER BY month;
```

> **Бизнес-смысл:** MAU показывает широту аудитории. Вместе с WAU и DAU используется для оценки «липкости» продукта.

### 4. ARPU / ARPPU

```sql
WITH daily_revenue AS (
    SELECT
        o.creation_time::date AS date,
        COUNT(DISTINCT o.order_id) AS orders,
        COUNT(DISTINCT o.user_id)  AS paying_users,
        SUM(p.price * oi.quantity) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN products p     ON p.product_id = oi.product_id
    WHERE o.order_id NOT IN (
        SELECT order_id FROM user_actions WHERE action = 'cancel_order'
    )
    GROUP BY o.creation_time::date
),
daily_users AS (
    SELECT time::date AS date, COUNT(DISTINCT user_id) AS users
    FROM user_actions
    GROUP BY time::date
)
SELECT
    r.date,
    ROUND(r.revenue::decimal / NULLIF(u.users, 0), 2)        AS arpu,
    ROUND(r.revenue::decimal / NULLIF(r.paying_users, 0), 2) AS arppu
FROM daily_revenue r
LEFT JOIN daily_users u USING (date)
ORDER BY r.date;
```

> **Бизнес-смысл:** ARPU — выручка на всех активных, ARPPU — на платящих. Отменённые заказы исключаются.

### 5. CR (Conversion Rate)

```sql
WITH daily_active AS (
    SELECT time::date AS date, COUNT(DISTINCT user_id) AS active_users
    FROM user_actions
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
    a.date,
    a.active_users,
    COALESCE(b.buyers, 0) AS buyers,
    ROUND(COALESCE(b.buyers, 0)::decimal / NULLIF(a.active_users, 0), 4) AS cr
FROM daily_active a
LEFT JOIN daily_buyers b USING (date)
ORDER BY a.date;
```

> **Бизнес-смысл:** CR — доля активных пользователей, совершивших покупку. Отменённые заказы исключаются.

### 6. Retention — базовый запрос

```sql
SELECT
    date_trunc('month', start_date)::date AS start_month,
    start_date,
    date - start_date AS day_number,
    users,
    ROUND(
        users::decimal / MAX(users) OVER (PARTITION BY start_date),
        2
    ) AS retention
FROM (
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
) t2
ORDER BY start_date, day_number;
```

> **Бизнес-смысл:** retention — ключевая метрика удержания. Показывает, сколько пользователей из когорты возвращаются через N дней.

### 7. Retention-матрица — дневная

Возвращает таблицу с колонками `start_month`, `start_date`, `cohort_size` и `0`–`15` с retention по дням. Пустые ячейки — `NULL` (когорта ещё не прожила столько дней).

```sql
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
    SELECT
        start_date,
        users AS cohort_size
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
    MAX(CASE WHEN day_number = 2  THEN retention END) AS "2",
    MAX(CASE WHEN day_number = 3  THEN retention END) AS "3",
    MAX(CASE WHEN day_number = 4  THEN retention END) AS "4",
    MAX(CASE WHEN day_number = 5  THEN retention END) AS "5",
    MAX(CASE WHEN day_number = 6  THEN retention END) AS "6",
    MAX(CASE WHEN day_number = 7  THEN retention END) AS "7",
    MAX(CASE WHEN day_number = 8  THEN retention END) AS "8",
    MAX(CASE WHEN day_number = 9  THEN retention END) AS "9",
    MAX(CASE WHEN day_number = 10 THEN retention END) AS "10",
    MAX(CASE WHEN day_number = 11 THEN retention END) AS "11",
    MAX(CASE WHEN day_number = 12 THEN retention END) AS "12",
    MAX(CASE WHEN day_number = 13 THEN retention END) AS "13",
    MAX(CASE WHEN day_number = 14 THEN retention END) AS "14",
    MAX(CASE WHEN day_number = 15 THEN retention END) AS "15"
FROM retention r
JOIN cohort_size cs ON cs.start_date = r.start_date
GROUP BY date_trunc('month', r.start_date)::date, r.start_date, cs.cohort_size
ORDER BY r.start_date;
```

**Что на выходе:**

| start_month | start_date | cohort_size | 0 | 1 | 2 | 3 | 4 | 5 | … | 15 |
|---|---|---|---|---|---|---|---|---|---|---|
| 2024-01-01 | 2024-01-01 | 45 | 1.00 | 0.14 | 0.15 | 0.18 | 0.19 | 0.14 | … | 0.07 |
| 2024-01-01 | 2024-01-02 | 38 | 1.00 | 0.18 | 0.16 | 0.19 | 0.17 | 0.19 | … | |
| 2024-01-01 | 2024-01-03 | 41 | 1.00 | 0.22 | 0.20 | 0.22 | 0.17 | 0.15 | … | |

> **Бизнес-смысл:** матрица позволяет сравнивать когорты между собой. `cohort_size` — размер когорты (число пользователей, впервые появившихся в этот день). `day_number = 0` всегда `1.00`. `NULL` — данных за этот день ещё нет.

### 8. Retention-матрица — недельная

```sql
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
    SELECT
        start_date,
        users AS cohort_size
    FROM cohort
    WHERE date = start_date
),
retention AS (
    SELECT
        start_date,
        (date - start_date) / 7 AS week_number,
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
    COALESCE(MAX(CASE WHEN week_number = 0 THEN retention END), 1.00) AS "w0",
    MAX(CASE WHEN week_number = 1 THEN retention END) AS "w1",
    MAX(CASE WHEN week_number = 2 THEN retention END) AS "w2",
    MAX(CASE WHEN week_number = 3 THEN retention END) AS "w3",
    MAX(CASE WHEN week_number = 4 THEN retention END) AS "w4",
    MAX(CASE WHEN week_number = 5 THEN retention END) AS "w5",
    MAX(CASE WHEN week_number = 6 THEN retention END) AS "w6",
    MAX(CASE WHEN week_number = 7 THEN retention END) AS "w7",
    MAX(CASE WHEN week_number = 8 THEN retention END) AS "w8"
FROM retention r
JOIN cohort_size cs ON cs.start_date = r.start_date
GROUP BY date_trunc('month', r.start_date)::date, r.start_date, cs.cohort_size
ORDER BY r.start_date;
```

> **Бизнес-смысл:** недельный шаг сглаживает шум и удобен, если ежедневные когорты слишком мелкие.

### 9. Retention-матрица — месячная

```sql
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
    SELECT
        start_date,
        users AS cohort_size
    FROM cohort
    WHERE date = start_date
),
retention AS (
    SELECT
        start_date,
        (
            (EXTRACT(YEAR  FROM date) - EXTRACT(YEAR  FROM start_date)) * 12
          + (EXTRACT(MONTH FROM date) - EXTRACT(MONTH FROM start_date))
        ) AS month_number,
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
    COALESCE(MAX(CASE WHEN month_number = 0 THEN retention END), 1.00) AS "m0",
    MAX(CASE WHEN month_number = 1 THEN retention END) AS "m1",
    MAX(CASE WHEN month_number = 2 THEN retention END) AS "m2",
    MAX(CASE WHEN month_number = 3 THEN retention END) AS "m3",
    MAX(CASE WHEN month_number = 4 THEN retention END) AS "m4",
    MAX(CASE WHEN month_number = 5 THEN retention END) AS "m5"
FROM retention r
JOIN cohort_size cs ON cs.start_date = r.start_date
GROUP BY date_trunc('month', r.start_date)::date, r.start_date, cs.cohort_size
ORDER BY r.start_date;
```

> **Бизнес-смысл:** месячная матрица — классический формат для отчётов по удержанию. `m0` — месяц первого появления, `m1` — следующий и т.д.

---

## 🔍 EXPLAIN ANALYZE

`EXPLAIN ANALYZE` показывает план выполнения запроса и реальное время по каждому шагу. Помогает понять, где запрос тормозит и используется ли индекс.

```sql
EXPLAIN ANALYZE
SELECT
    date_trunc('week', time) AS week,
    COUNT(DISTINCT user_id)  AS wau
FROM user_actions
GROUP BY date_trunc('week', time);
```

Что смотреть в выводе:

- **`Seq Scan`** — чтение всей таблицы. На маленьких таблицах это нормально и быстрее индекса.
- **`Index Scan`** — чтение через индекс. Появляется на больших объёмах, если индекс есть.
- **`actual time=...`** — реальное время шага.
- **`rows=...`** — сколько строк прошло через шаг.

Проверить, что индекс рабочий, можно так:

```sql
SET enable_seqscan = off;
EXPLAIN ANALYZE
SELECT date_trunc('week', time) AS week, COUNT(DISTINCT user_id) AS wau
FROM user_actions
GROUP BY date_trunc('week', time);
SET enable_seqscan = on;
```

В плане появится `Index Scan` по `idx_actions_time` — значит, индекс существует и может быть использован.

## 📌 Что демонстрирует проект

- Навык проектирования нормализованной реляционной схемы под аналитические нагрузки (факт + измерения, PK/FK).
- Умение писать аналитические запросы на PostgreSQL: оконные функции, CTE, `FILTER`, множественные `JOIN`.
- Знание оптимизаций: индексы, `EXPLAIN ANALYZE`, понимание планов запросов.
- Воспроизводимая генерация данных через `setseed` — одинаковый результат при каждом запуске.
- Retention-матрицы в трёх разрезах (день, неделя, месяц) с колонкой `cohort_size`.
- Работа с продуктовыми метриками маркетплейса: DAU, WAU, MAU, ARPU, ARPPU, CR, retention.

## 🔗 Интерактивная демонстрация

[Открыть в SQLize.online — PostgreSQL](https://sqlize.online/sql/psql/)
