# PostgreSQL Marketplace Analytics

Аналитический проект на PostgreSQL: расчёт продуктовых метрик маркетплейса (GMV, воронка продавцов, retention) на реляционной схеме с индексами.

## 📖 О проекте

Проект показывает полный цикл работы с PostgreSQL: проектирование схемы, загрузку данных и расчёт метрик. Цель — продемонстрировать навыки работы с реляционной СУБД и понимание того, чем аналитическая (OLAP) нагрузка отличается от транзакционной (OLTP).

Проект отвечает на вопросы: как спроектировать нормализованную схему под аналитику маркетплейса, как эффективно считать GMV и удержание, как использовать оконные функции для ранжирования и накопительных итогов. В качестве примера используется маркетплейс: заказы, продавцы, покупатели, товары и города. Такой сценарий хорошо знаком любому продуктовому аналитику и позволяет показать реальные метрики: GMV, топ продавцов, средний чек, retention, география.

## 🛠️ Технологии

- **PostgreSQL** — оконные функции, CTE, FILTER, индексы, EXPLAIN ANALYZE
- **SQL** — агрегации, JOIN, DATE_TRUNC, работа с датами
- **SQLize.online** — онлайн-песочница для запуска

## 📊 Схема данных

Пять таблиц: `orders` (факт), `sellers`, `users`, `products`, `cities` (измерения). 

### Таблица `cities`

| Колонка   | Тип         | Описание           |
|-----------|-------------|--------------------|
| city_id   | INT         | ID города (PK)     |
| city_name | VARCHAR(50) | Название города    |

### Таблица `sellers`

| Колонка     | Тип          | Описание                  |
|-------------|--------------|---------------------------|
| seller_id   | INT          | ID продавца (PK)          |
| seller_name | VARCHAR(100) | Название                  |
| join_dt     | DATE         | Дата регистрации          |
| city_id     | INT          | ID города (FK → cities)   |

### Таблица `users`

| Колонка   | Тип          | Описание                  |
|-----------|--------------|---------------------------|
| user_id   | INT          | ID покупателя (PK)        |
| user_name | VARCHAR(100) | Имя                       |
| reg_dt    | DATE         | Дата регистрации          |
| city_id   | INT          | ID города (FK → cities)   |

### Таблица `products`

| Колонка      | Тип           | Описание             |
|--------------|---------------|----------------------|
| product_id   | INT           | ID товара (PK)       |
| product_name | VARCHAR(200)  | Название             |
| category     | VARCHAR(50)   | Категория            |
| price        | NUMERIC(10,2) | Цена                 |

### Таблица `orders`

| Колонка    | Тип           | Описание                |
|------------|---------------|-------------------------|
| order_id   | INT           | ID заказа (PK)          |
| order_dt   | DATE          | Дата заказа             |
| seller_id  | INT           | ID продавца (FK)        |
| product_id | INT           | ID товара (FK)          |
| user_id    | INT           | ID покупателя (FK)      |
| quantity   | INT           | Количество              |
| revenue    | NUMERIC(12,2) | Выручка                 |
| region     | VARCHAR(50)   | Регион доставки         |

> **О данных:** Набор данных синтетический и создан исключительно для демонстрации возможностей PostgreSQL. Все `seller_id`, `user_id`, названия и временные метки сгенерированы. Проект не использует реальные логи, персональные данные или коммерческую информацию.

Особенности схемы: `PRIMARY KEY` на `order_id` гарантирует уникальность заказов; `REFERENCES` обеспечивают ссылочную целостность между фактом и измерениями; `NUMERIC(12,2)` и `NUMERIC(10,2)` используются для денежных значений, чтобы избежать ошибок округления `FLOAT`; индексы на `order_dt`, `seller_id`, `region`, `user_id` ускоряют аналитические запросы с фильтрацией и `JOIN`; `city_id` в `sellers` и `users` позволяет анализировать географию продавцов и покупателей независимо от региона доставки; категория товара вынесена только в `products`, так как один продавец может работать в нескольких категориях.

### Пример данных

Несколько строк из таблицы `orders` для наглядности:

| order_id | order_dt   | seller_id | product_id | user_id | quantity | revenue | region  |
|----------|------------|-----------|------------|---------|----------|---------|---------|
| 1001     | 2026-10-02 | 1         | 101        | 501     | 1        | 45000   | Москва  |
| 1002     | 2026-10-02 | 1         | 102        | 501     | 2        | 16000   | Москва  |
| 1003     | 2026-10-02 | 2         | 103        | 502     | 3        | 3600    | СПб     |
| 1004     | 2026-10-02 | 3         | 104        | 503     | 1        | 35000   | Москва  |
| 1005     | 2026-10-02 | 4         | 105        | 504     | 1        | 60000   | Казань  |
| 1006     | 2026-10-02 | 5         | 106        | 507     | 2        | 5000    | Новосибирск |
| 1007     | 2026-10-02 | 1         | 102        | 508     | 1        | 8000    | Москва  |

## 🚀 Запуск проекта

Все шаги выполняются в [SQLize.online — PostgreSQL](https://sqlize.online/sql/psql/).

> ⚠️ **Важно:** SQLize.online не сохраняет состояние между отдельными запусками. Каждый `Run` создаёт новую временную базу данных. Поэтому весь код ниже нужно выполнить за один запуск, а не по частям.

### Создание таблиц

```sql
-- 1. Создание таблиц
CREATE TABLE cities (
    city_id   INT PRIMARY KEY,
    city_name VARCHAR(50) NOT NULL
);

CREATE TABLE sellers (
    seller_id   INT PRIMARY KEY,
    seller_name VARCHAR(100) NOT NULL,
    join_dt     DATE NOT NULL,
    city_id     INT NOT NULL REFERENCES cities(city_id)
);

CREATE TABLE users (
    user_id   INT PRIMARY KEY,
    user_name VARCHAR(100) NOT NULL,
    reg_dt    DATE NOT NULL,
    city_id   INT NOT NULL REFERENCES cities(city_id)
);

CREATE TABLE products (
    product_id   INT PRIMARY KEY,
    product_name VARCHAR(200) NOT NULL,
    category     VARCHAR(50) NOT NULL,
    price        NUMERIC(10,2) NOT NULL
);

CREATE TABLE orders (
    order_id   INT PRIMARY KEY,
    order_dt   DATE NOT NULL,
    seller_id  INT NOT NULL REFERENCES sellers(seller_id),
    product_id INT NOT NULL REFERENCES products(product_id),
    user_id    INT NOT NULL REFERENCES users(user_id),
    quantity   INT NOT NULL,
    revenue    NUMERIC(12,2) NOT NULL,
    region     VARCHAR(50) NOT NULL
);

-- 2. Создание индексов
CREATE INDEX idx_orders_dt     ON orders(order_dt);
CREATE INDEX idx_orders_seller ON orders(seller_id);
CREATE INDEX idx_orders_region ON orders(region);
CREATE INDEX idx_orders_user   ON orders(user_id);
CREATE INDEX idx_sellers_city  ON sellers(city_id);
CREATE INDEX idx_users_city    ON users(city_id);

-- 3. Добавление данных
INSERT INTO cities VALUES
(1, 'Москва'),
(2, 'Санкт-Петербург'),
(3, 'Казань'),
(4, 'Новосибирск'),
(5, 'Екатеринбург');

INSERT INTO sellers VALUES
(1, 'TechStore', '2025-01-15', 1),
(2, 'BookWorld', '2025-02-01', 2),
(3, 'HomeStyle', '2025-01-20', 1),
(4, 'SportLife', '2025-03-10', 3),
(5, 'KidsToys',  '2025-02-15', 4);

INSERT INTO users VALUES
(501, 'Иван Петров',      '2025-01-10', 1),
(502, 'Анна Смирнова',    '2025-02-12', 2),
(503, 'Олег Кузнецов',    '2025-01-25', 1),
(504, 'Мария Иванова',    '2025-03-01', 3),
(505, 'Дмитрий Соколов',  '2025-02-18', 2),
(506, 'Елена Попова',     '2025-01-30', 1),
(507, 'Сергей Лебедев',   '2025-03-05', 4),
(508, 'Наталья Козлова',  '2025-02-22', 3),
(509, 'Артем Новиков',    '2025-03-12', 5);

INSERT INTO products VALUES
(101, 'Смартфон X',        'Электроника',     45000),
(102, 'Наушники Y',        'Электроника',      8000),
(103, 'Книга "Аналитика"', 'Книги',             1200),
(104, 'Кофемашина Z',      'Дом',              35000),
(105, 'Беговая дорожка',   'Спорт',            60000),
(106, 'Конструктор',       'Детские товары',    2500);

INSERT INTO orders VALUES
(1001, DATE '2026-10-02', 1, 101, 501, 1, 45000, 'Москва'),
(1002, DATE '2026-10-02', 1, 102, 501, 2, 16000, 'Москва'),
(1003, DATE '2026-10-02', 2, 103, 502, 3,  3600, 'СПб'),
(1004, DATE '2026-10-02', 3, 104, 503, 1, 35000, 'Москва'),
(1005, DATE '2026-10-02', 4, 105, 504, 1, 60000, 'Казань'),
(1006, DATE '2026-10-02', 5, 106, 507, 2,  5000, 'Новосибирск'),
(1007, DATE '2026-10-02', 1, 102, 508, 1,  8000, 'Москва'),
(1008, DATE '2026-10-03', 1, 101, 501, 1, 45000, 'Москва'),
(1009, DATE '2026-10-03', 2, 103, 502, 5,  6000, 'СПб'),
(1010, DATE '2026-10-03', 3, 104, 503, 2, 70000, 'СПб'),
(1011, DATE '2026-10-03', 4, 105, 504, 1, 60000, 'Москва'),
(1012, DATE '2026-10-03', 5, 106, 505, 3,  7500, 'Москва'),
(1013, DATE '2026-10-03', 1, 102, 506, 1,  8000, 'Москва'),
(1014, DATE '2026-10-03', 2, 103, 509, 2,  2400, 'СПб'),
(1015, DATE '2026-10-04', 1, 101, 501, 1, 45000, 'Москва'),
(1016, DATE '2026-10-04', 1, 102, 502, 1,  8000, 'СПб'),
(1017, DATE '2026-10-04', 3, 104, 504, 1, 35000, 'Казань'),
(1018, DATE '2026-10-04', 4, 105, 504, 1, 60000, 'Москва'),
(1019, DATE '2026-10-04', 5, 106, 505, 2,  5000, 'Москва'),
(1020, DATE '2026-10-04', 2, 103, 506, 3,  3600, 'Москва'),
(1021, DATE '2026-10-04', 1, 101, 507, 1, 45000, 'Новосибирск'),
(1022, DATE '2026-10-04', 3, 104, 508, 1, 35000, 'Москва'),
(1023, DATE '2026-10-05', 1, 101, 501, 1, 45000, 'Москва'),
(1024, DATE '2026-10-05', 2, 103, 502, 4,  4800, 'СПб'),
(1025, DATE '2026-10-05', 3, 104, 503, 1, 35000, 'Москва'),
(1026, DATE '2026-10-05', 4, 105, 504, 1, 60000, 'Казань'),
(1027, DATE '2026-10-05', 5, 106, 505, 3,  7500, 'Москва'),
(1028, DATE '2026-10-05', 1, 102, 506, 2, 16000, 'Москва'),
(1029, DATE '2026-10-05', 2, 103, 507, 5,  6000, 'Новосибирск'),
(1030, DATE '2026-10-05', 4, 105, 508, 1, 60000, 'Москва'),
(1031, DATE '2026-10-05', 5, 106, 509, 2,  5000, 'СПб'),
(1032, DATE '2026-10-06', 1, 101, 501, 1, 45000, 'Москва'),
(1033, DATE '2026-10-06', 1, 102, 502, 1,  8000, 'СПб'),
(1034, DATE '2026-10-06', 3, 104, 503, 2, 70000, 'СПб'),
(1035, DATE '2026-10-06', 4, 105, 504, 1, 60000, 'Москва'),
(1036, DATE '2026-10-06', 5, 106, 505, 1,  2500, 'Москва'),
(1037, DATE '2026-10-06', 2, 103, 506, 3,  3600, 'Москва'),
(1038, DATE '2026-10-06', 1, 101, 507, 1, 45000, 'Новосибирск'),
(1039, DATE '2026-10-06', 3, 104, 508, 1, 35000, 'Москва'),
(1040, DATE '2026-10-06', 4, 105, 509, 1, 60000, 'СПб'),
(1041, DATE '2026-10-07', 1, 101, 501, 1, 45000, 'Москва'),
(1042, DATE '2026-10-07', 2, 103, 502, 2,  2400, 'СПб'),
(1043, DATE '2026-10-07', 3, 104, 503, 1, 35000, 'Москва'),
(1044, DATE '2026-10-07', 4, 105, 504, 1, 60000, 'Казань'),
(1045, DATE '2026-10-07', 5, 106, 505, 2,  5000, 'Москва'),
(1046, DATE '2026-10-07', 1, 102, 506, 1,  8000, 'Москва'),
(1047, DATE '2026-10-07', 2, 103, 507, 3,  3600, 'Новосибирск'),
(1048, DATE '2026-10-07', 3, 104, 508, 2, 70000, 'Москва'),
(1049, DATE '2026-10-07', 4, 105, 509, 1, 60000, 'СПб'),
(1050, DATE '2026-10-08', 1, 101, 501, 1, 45000, 'Москва'),
(1051, DATE '2026-10-08', 1, 102, 502, 1,  8000, 'СПб'),
(1052, DATE '2026-10-08', 2, 103, 503, 2,  2400, 'Москва'),
(1053, DATE '2026-10-08', 3, 104, 504, 1, 35000, 'Казань'),
(1054, DATE '2026-10-08', 4, 105, 505, 1, 60000, 'Москва'),
(1055, DATE '2026-10-08', 5, 106, 506, 3,  7500, 'Москва'),
(1056, DATE '2026-10-08', 1, 101, 507, 1, 45000, 'Новосибирск'),
(1057, DATE '2026-10-08', 2, 103, 508, 2,  2400, 'Москва'),
(1058, DATE '2026-10-08', 3, 104, 509, 1, 35000, 'СПб'),
(1059, DATE '2026-10-08', 4, 105, 501, 1, 60000, 'Москва'),
(1060, DATE '2026-10-08', 5, 106, 502, 2,  5000, 'СПб');
```

## 📈 Аналитические запросы

### 1. GMV, количество заказов и покупателей
```sql
SELECT
    SUM(revenue)              AS gmv,
    COUNT(DISTINCT order_id)  AS orders_count,
    COUNT(DISTINCT user_id)   AS buyers_count
FROM orders;
```
**Результат:**
| gmv        | orders_count | buyers_count |
|------------|--------------|--------------|
| 1770800.00 | 60           | 9            |

> **Бизнес-смысл:** базовая метрика объёма продаж на маркетплейсе. По нему оценивают динамику всего бизнеса.

### 2. Топ продавцов по выручке (с городом)
```sql
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
```
**Результат:**
| seller_id | seller_name | city_name       | total_revenue | orders_cnt | avg_order_value |
|-----------|-------------|-----------------|---------------|------------|-----------------|
| 4         | SportLife   | Казань          | 660000.00     | 11         | 60000.00        |
| 1         | TechStore   | Москва          | 530000.00     | 18         | 29444.44        |
| 3         | HomeStyle   | Москва          | 490000.00     | 11         | 44545.45        |
| 5         | KidsToys    | Новосибирск     | 50000.00      | 9          | 5555.56         |
| 2         | BookWorld   | Санкт-Петербург | 40800.00      | 11         | 3709.09         |

> **Бизнес-смысл:** рейтинг продавцов — основа для программ лояльности, скидок на комиссию и приоритета в выдаче. Город продавца помогает понять географию предложения.

### 3. Выручка по регионам доставки
```sql
SELECT
    region,
    SUM(revenue)              AS revenue,
    COUNT(DISTINCT order_id)  AS orders_cnt,
    COUNT(DISTINCT user_id)   AS buyers
FROM orders
GROUP BY region
ORDER BY revenue DESC;
```
**Результат:**
| region      | revenue    | orders_cnt | buyers |
|-------------|------------|------------|--------|
| Москва      | 1023000.00 | 34         | 6      |
| СПб         | 348200.00  | 15         | 3      |
| Казань      | 250000.00  | 5          | 1      |
| Новосибирск | 149600.00  | 6          | 1      |

> **Бизнес-смысл:** распределение выручки по регионам доставки — база для логистики, региональных промо и планирования складов.

### 4. Динамика GMV по дням с накопительным итогом
```sql
SELECT
    order_dt,
    SUM(revenue) AS daily_gmv,
    COUNT(DISTINCT order_id) AS daily_orders,
    SUM(SUM(revenue)) OVER (ORDER BY order_dt) AS cumulative_gmv
FROM orders
GROUP BY order_dt
ORDER BY order_dt;
```
**Результат:**
| order_dt   | daily_gmv | daily_orders | cumulative_gmv |
|------------|-----------|--------------|----------------|
| 2026-10-02 | 172600.00 | 7            | 172600.00      |
| 2026-10-03 | 198900.00 | 7            | 371500.00      |
| 2026-10-04 | 236600.00 | 8            | 608100.00      |
| 2026-10-05 | 239300.00 | 9            | 847400.00      |
| 2026-10-06 | 329100.00 | 9            | 1176500.00     |
| 2026-10-07 | 289000.00 | 9            | 1465500.00     |
| 2026-10-08 | 305300.00 | 11           | 1770800.00     |

> **Бизнес-смысл:** ежедневная динамика и накопленный GMV — инструмент для отслеживания трендов и сезонности.

### 5. Retention покупателей (активные дни, с городом)
```sql
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
```
**Результат:**
| user_id | user_name       | city_name       | active_days | first_order | last_order | lifetime_revenue |
|---------|-----------------|-----------------|-------------|-------------|------------|------------------|
| 504     | Мария Иванова   | Казань          | 7           | 2026-10-02  | 2026-10-08 | 430000.00        |
| 501     | Иван Петров     | Москва          | 7           | 2026-10-02  | 2026-10-08 | 391000.00        |
| 502     | Анна Смирнова   | Санкт-Петербург | 7           | 2026-10-02  | 2026-10-08 | 45800.00         |
| 503     | Олег Кузнецов   | Москва          | 6           | 2026-10-02  | 2026-10-08 | 247400.00        |
| 508     | Наталья Козлова | Казань          | 6           | 2026-10-02  | 2026-10-08 | 210400.00        |
| 507     | Сергей Лебедев  | Новосибирск     | 6           | 2026-10-02  | 2026-10-08 | 149600.00        |
| 505     | Дмитрий Соколов | Санкт-Петербург | 6           | 2026-10-03  | 2026-10-08 | 87500.00         |
| 506     | Елена Попова    | Москва          | 6           | 2026-10-03  | 2026-10-08 | 46700.00         |
| 509     | Артем Новиков   | Екатеринбург    | 5           | 2026-10-03  | 2026-10-08 | 162400.00        |

> **Бизнес-смысл:** retention — ключевая метрика удержания. Показывает, сколько дней покупатель возвращался. LTV (lifetime_revenue) помогает оценить ценность клиента.

### 6. Средний чек по регионам доставки
```sql
SELECT
    region,
    ROUND(SUM(revenue) / COUNT(DISTINCT order_id), 2) AS avg_order_value,
    ROUND(AVG(revenue), 2) AS avg_line_value
FROM orders
GROUP BY region
ORDER BY avg_order_value DESC;
```
**Результат:**
| region      | avg_order_value | avg_line_value |
|-------------|-----------------|----------------|
| Казань      | 50000.00        | 50000.00       |
| Москва      | 30088.24        | 30088.24       |
| Новосибирск | 24933.33        | 24933.33       |
| СПб         | 23213.33        | 23213.33       |

> **Бизнес-смысл:** средний чек по регионам — индикатор платёжеспособности и потребительского поведения. Используется для таргетинга промо.

### 7. Разбивка заказов по регионам доставки через FILTER
```sql
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
```
**Результат:**
| seller_id | seller_name | orders_msk | orders_spb | orders_other |
|-----------|-------------|------------|------------|--------------|
| 1         | TechStore   | 12         | 3          | 3            |
| 2         | BookWorld   | 4          | 5          | 2            |
| 3         | HomeStyle   | 6          | 3          | 2            |
| 4         | SportLife   | 6          | 2          | 3            |
| 5         | KidsToys    | 6          | 2          | 1            |

> **Бизнес-смысл:** условные агрегации через `FILTER` позволяют в одном запросе разбить заказы по ключевым регионам. Удобно для дашбордов.

### 8. Ранжирование продавцов внутри категорий товаров
```sql
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
```
**Результат:**
| category       | seller_id | seller_name | city_name       | total_revenue | rank_in_category |
|----------------|-----------|-------------|-----------------|---------------|------------------|
| Детские товары | 5         | KidsToys    | Новосибирск     | 50000.00      | 1                |
| Дом            | 3         | HomeStyle   | Москва          | 490000.00     | 1                |
| Книги          | 2         | BookWorld   | Санкт-Петербург | 40800.00      | 1                |
| Спорт          | 4         | SportLife   | Казань          | 660000.00     | 1                |
| Электроника    | 1         | TechStore   | Москва          | 530000.00     | 1                |

> **Бизнес-смысл:** рейтинг продавцов внутри категории — основа для категорийного менеджмента.

### 9. Топ товаров по выручке
```sql
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
```
**Результат:**
| product_id | product_name    | category       | total_qty | total_revenue |
|------------|-----------------|----------------|-----------|---------------|
| 105        | Беговая дорожка | Спорт          | 11        | 660000.00     |
| 104        | Кофемашина Z    | Дом            | 14        | 490000.00     |
| 101        | Смартфон X      | Электроника    | 10        | 450000.00     |
| 102        | Наушники Y      | Электроника    | 10        | 80000.00      |
| 106        | Конструктор     | Детские товары | 20        | 50000.00      |

> **Бизнес-смысл:** топ товаров — база для управления ассортиментом, промо и запасами. Помогает понять, что «вытягивает» выручку.

### 10. География: покупатели и продавцы по городам
```sql
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
```
**Результат:**
| city_id | city_name       | sellers_cnt | buyers_cnt |
|---------|-----------------|-------------|------------|
| 1       | Москва          | 2           | 3          |
| 2       | Санкт-Петербург | 1           | 2          |
| 3       | Казань          | 1           | 2          |
| 4       | Новосибирск     | 1           | 1          |
| 5       | Екатеринбург    | 0           | 1          |

> **Бизнес-смысл:** сравнение предложения (продавцы) и спроса (покупатели) по городам. Помогает найти города с дефицитом продавцов — точки роста.

### 11. Продавцы и их покупатели из одного города
```sql
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
```
**Результат:**
| seller_id | seller_name | city_name       | buyers_from_same_city |
|-----------|-------------|-----------------|-----------------------|
| 1         | TechStore   | Москва          | 2                     |
| 4         | SportLife   | Казань          | 2                     |
| 2         | BookWorld   | Санкт-Петербург | 1                     |
| 3         | HomeStyle   | Москва          | 1                     |
| 5         | KidsToys    | Новосибирск     | 1                     |

> **Бизнес-смысл:** показывает, как часто покупатели заказывают у продавцов из своего города. Важно для логистики (быстрая доставка) и локальных промо.

### 12. Оптимизация: EXPLAIN ANALYZE
```sql
EXPLAIN ANALYZE
SELECT region, SUM(revenue)
FROM orders
WHERE order_dt >= DATE '2026-10-05'
GROUP BY region;
```
**Результат (план запроса):**
| QUERY PLAN                                                                                                    |
|---------------------------------------------------------------------------------------------------------------|
| HashAggregate  (cost=16.09..17.54 rows=116 width=150) (actual time=0.069..0.072 rows=4.00 loops=1)            |
|   Group Key: region                                                                                           |
|   Batches: 1  Memory Usage: 32kB                                                                              |
|   Buffers: shared hit=1                                                                                       |
|   ->  Seq Scan on orders  (cost=0.00..15.38 rows=143 width=134) (actual time=0.030..0.035 rows=38.00 loops=1) |
|         Filter: (order_dt >= '2026-10-05'::date)                                                              |
|         Rows Removed by Filter: 22                                                                            |
|         Buffers: shared hit=1                                                                                 |
| Planning:                                                                                                     |
|   Buffers: shared hit=3                                                                                       |
| Planning Time: 0.275 ms                                                                                       |
| Execution Time: 0.146 ms                                                                                      |


> **Бизнес-смысл:** демонстрация понимания планов запросов. На таблице из 60 строк оптимизатор выбирает `Seq Scan`, потому что последовательное чтение дешевле, чем доступ через индекс. Это нормальное поведение планировщика: **индекс используется только тогда, когда он реально быстрее**. На реальных объёмах (миллионы заказов) при таком же запросе PostgreSQL выберет `Index Scan` по `idx_orders_dt` — именно для этого индекс и создавался. Проверить это можно, временно отключив `Seq Scan` через `SET enable_seqscan = off` перед запросом.

## 📁 Структура проекта

```
postgresql-marketplace-analytics/
├── README.md
├── schema.sql        # CREATE TABLE + индексы
├── insert_data.sql   # INSERT
└── queries.sql       # аналитические запросы
```

## 📌 Что демонстрирует проект

- Понимание разницы между OLTP и OLAP (PostgreSQL vs ClickHouse).
- Навык проектирования нормализованной реляционной схемы под аналитические нагрузки (факт + измерения, PK/FK, справочник городов).
- Умение писать аналитические запросы на PostgreSQL: оконные функции, CTE, `FILTER`, множественные `JOIN`.
- Знание оптимизаций: индексы, `EXPLAIN ANALYZE`, понимание планов запросов.
- Понимание важности группировки по ID, а не по именам.
- Работа с продуктовыми метриками маркетплейса: GMV, топ продавцов, retention, средний чек, география продавцов и покупателей.

## 🔗 Интерактивная демонстрация

[Открыть в SQLize.online — PostgreSQL](https://sqlize.online/sql/psql18/5dded27cc226a54fda3d8ee935ebf8b3/)
