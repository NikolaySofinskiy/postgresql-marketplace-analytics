# PostgreSQL Marketplace Analytics

Аналитический проект на PostgreSQL: расчёт продуктовых метрик маркетплейса (DAU, WAU, MAU, ARPU, ARPPU, CR, Retention) на реляционной схеме с индексами. Данные вставляются явно через `INSERT` — без генерации и `random()`, все строки фиксированы, метрики воспроизводимы по определению.

## 📖 О проекте

Проект показывает полный цикл работы с PostgreSQL: проектирование схемы, загрузку данных и расчёт продуктовых метрик. Цель — продемонстрировать навыки работы с PostgreSQL и понимание продуктовых метрик маркетплейса.

Проект отвечает на вопросы: как спроектировать нормализованную схему под аналитику маркетплейса, как эффективно считать DAU/WAU/MAU, как использовать оконные функции для retention-матрицы. В качестве примера используется маркетплейс: заказы, покупатели, товары и действия пользователей.

Данные покрывают четыре месяца (январь–апрель 2024), что даёт полноценные DAU, WAU, MAU и дневные, недельные и месячные когорты для retention.

## 🛠️ Технологии

- **PostgreSQL** — оконные функции, CTE, `FILTER`, индексы, `date_trunc`, `EXPLAIN ANALYZE`
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

> **О данных:** Набор данных синтетический и создан исключительно для демонстрации возможностей PostgreSQL. Проект не использует реальные логи, персональные данные или коммерческую информацию.

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

### 2. Загрузка данных

#### 2.1. Пользователи и товары

```sql
INSERT INTO users (user_id, user_name, reg_dt, city) VALUES
(1,  'Иван Петров',        DATE '2024-01-01', 'Москва'),
(2,  'Анна Смирнова',      DATE '2024-01-01', 'СПб'),
(3,  'Олег Кузнецов',      DATE '2024-01-01', 'Москва'),
(4,  'Мария Иванова',      DATE '2024-01-01', 'Казань'),
(5,  'Дмитрий Соколов',    DATE '2024-01-01', 'СПб'),
(6,  'Елена Попова',       DATE '2024-01-01', 'Москва'),
(7,  'Сергей Лебедев',     DATE '2024-01-01', 'Новосибирск'),
(8,  'Наталья Козлова',    DATE '2024-01-01', 'Казань'),
(9,  'Артем Новиков',      DATE '2024-01-01', 'Екатеринбург'),
(10, 'Ольга Морозова',     DATE '2024-01-01', 'Москва'),
(11, 'Павел Волков',       DATE '2024-01-01', 'СПб'),
(12, 'Татьяна Соловьева',  DATE '2024-01-01', 'Москва'),
(13, 'Андрей Васильев',    DATE '2024-01-01', 'Казань'),
(14, 'Юлия Захарова',      DATE '2024-01-01', 'СПб'),
(15, 'Максим Павлов',      DATE '2024-01-01', 'Москва'),
(16, 'Светлана Семенова',  DATE '2024-01-01', 'Новосибирск'),
(17, 'Николай Голубев',    DATE '2024-01-01', 'Москва'),
(18, 'Екатерина Виноградова', DATE '2024-02-01', 'Екатеринбург'),
(19, 'Роман Богданов',     DATE '2024-02-01', 'СПб'),
(20, 'Ирина Воробьева',    DATE '2024-02-01', 'Москва'),
(21, 'Алексей Федоров',    DATE '2024-02-01', 'Казань'),
(22, 'Марина Михайлова',   DATE '2024-03-01', 'СПб'),
(23, 'Денис Беляев',       DATE '2024-03-01', 'Москва'),
(24, 'Ксения Тарасова',    DATE '2024-03-01', 'Новосибирск'),
(25, 'Владимир Белов',     DATE '2024-03-01', 'Москва'),
(26, 'Анастасия Комарова', DATE '2024-03-01', 'Екатеринбург'),
(27, 'Григорий Орлов',     DATE '2024-04-01', 'СПб'),
(28, 'Людмила Киселева',   DATE '2024-04-01', 'Москва'),
(29, 'Станислав Макаров',  DATE '2024-04-01', 'Казань'),
(30, 'Валентина Андреева', DATE '2024-04-01', 'СПб');

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

#### 2.2. Заказы

```sql
INSERT INTO orders (order_id, user_id, creation_time, status) VALUES
-- Январь
(1001, 1,  TIMESTAMP '2024-01-02 10:15:00', 'created'),
(1002, 2,  TIMESTAMP '2024-01-02 12:30:00', 'created'),
(1003, 3,  TIMESTAMP '2024-01-03 14:00:00', 'created'),
(1004, 4,  TIMESTAMP '2024-01-03 15:45:00', 'created'),
(1005, 5,  TIMESTAMP '2024-01-04 17:10:00', 'canceled'),
(1006, 6,  TIMESTAMP '2024-01-05 19:25:00', 'created'),
(1007, 7,  TIMESTAMP '2024-01-06 09:00:00', 'created'),
(1008, 8,  TIMESTAMP '2024-01-07 10:30:00', 'created'),
(1009, 9,  TIMESTAMP '2024-01-08 12:00:00', 'created'),
(1010, 10, TIMESTAMP '2024-01-09 13:15:00', 'created'),
(1011, 1,  TIMESTAMP '2024-01-10 15:40:00', 'created'),
(1012, 2,  TIMESTAMP '2024-01-11 17:00:00', 'created'),
(1013, 3,  TIMESTAMP '2024-01-12 19:20:00', 'canceled'),
(1014, 11, TIMESTAMP '2024-01-13 08:45:00', 'created'),
(1015, 12, TIMESTAMP '2024-01-14 10:00:00', 'created'),
(1016, 13, TIMESTAMP '2024-01-15 11:30:00', 'created'),
(1017, 4,  TIMESTAMP '2024-01-16 13:00:00', 'created'),
(1018, 14, TIMESTAMP '2024-01-17 14:30:00', 'created'),
(1019, 5,  TIMESTAMP '2024-01-18 16:00:00', 'created'),
(1020, 15, TIMESTAMP '2024-01-19 18:15:00', 'created'),
(1021, 6,  TIMESTAMP '2024-01-20 09:15:00', 'created'),
(1022, 16, TIMESTAMP '2024-01-21 10:45:00', 'created'),
(1023, 17, TIMESTAMP '2024-01-22 12:00:00', 'created'),
(1024, 7,  TIMESTAMP '2024-01-23 13:30:00', 'created'),
(1025, 8,  TIMESTAMP '2024-01-24 15:00:00', 'canceled'),
(1026, 9,  TIMESTAMP '2024-01-25 17:20:00', 'created'),
(1027, 10, TIMESTAMP '2024-01-26 19:00:00', 'created'),
(1028, 1,  TIMESTAMP '2024-01-27 08:30:00', 'created'),
(1029, 2,  TIMESTAMP '2024-01-28 10:00:00', 'created'),
(1030, 3,  TIMESTAMP '2024-01-29 11:30:00', 'created'),
(1031, 4,  TIMESTAMP '2024-01-30 13:00:00', 'created'),
(1032, 5,  TIMESTAMP '2024-01-31 14:15:00', 'created'),
-- Февраль
(1033, 6,  TIMESTAMP '2024-02-01 15:45:00', 'created'),
(1034, 7,  TIMESTAMP '2024-02-03 17:00:00', 'created'),
(1035, 8,  TIMESTAMP '2024-02-05 19:30:00', 'canceled'),
(1036, 9,  TIMESTAMP '2024-02-07 09:00:00', 'created'),
(1037, 10, TIMESTAMP '2024-02-09 10:30:00', 'created'),
(1038, 1,  TIMESTAMP '2024-02-11 12:00:00', 'created'),
(1039, 2,  TIMESTAMP '2024-02-13 13:45:00', 'created'),
(1040, 11, TIMESTAMP '2024-02-15 15:15:00', 'created'),
(1041, 12, TIMESTAMP '2024-02-17 17:00:00', 'created'),
(1042, 13, TIMESTAMP '2024-02-19 19:00:00', 'created'),
(1043, 14, TIMESTAMP '2024-02-21 08:45:00', 'created'),
(1044, 15, TIMESTAMP '2024-02-23 10:15:00', 'created'),
(1045, 16, TIMESTAMP '2024-02-25 11:45:00', 'created'),
(1046, 17, TIMESTAMP '2024-02-26 13:15:00', 'canceled'),
(1047, 18, TIMESTAMP '2024-02-27 15:00:00', 'created'),
(1048, 19, TIMESTAMP '2024-02-28 17:30:00', 'created'),
(1049, 20, TIMESTAMP '2024-02-29 19:15:00', 'created'),
(1050, 3,  TIMESTAMP '2024-02-02 09:30:00', 'created'),
(1051, 4,  TIMESTAMP '2024-02-04 11:00:00', 'created'),
(1052, 5,  TIMESTAMP '2024-02-06 12:30:00', 'created'),
(1053, 21, TIMESTAMP '2024-02-08 14:00:00', 'created'),
(1054, 6,  TIMESTAMP '2024-02-10 15:30:00', 'created'),
(1055, 7,  TIMESTAMP '2024-02-12 17:00:00', 'created'),
(1056, 8,  TIMESTAMP '2024-02-14 19:30:00', 'created'),
(1057, 9,  TIMESTAMP '2024-02-16 20:00:00', 'created'),
(1058, 10, TIMESTAMP '2024-02-18 21:00:00', 'created'),
(1059, 11, TIMESTAMP '2024-02-20 22:00:00', 'created'),
(1060, 12, TIMESTAMP '2024-02-22 10:00:00', 'created'),
(1061, 13, TIMESTAMP '2024-02-24 11:30:00', 'created'),
(1062, 14, TIMESTAMP '2024-02-26 13:00:00', 'created'),
-- Март
(1063, 1,  TIMESTAMP '2024-03-01 09:00:00', 'created'),
(1064, 2,  TIMESTAMP '2024-03-03 10:30:00', 'created'),
(1065, 3,  TIMESTAMP '2024-03-05 12:00:00', 'canceled'),
(1066, 4,  TIMESTAMP '2024-03-07 13:45:00', 'created'),
(1067, 5,  TIMESTAMP '2024-03-09 15:15:00', 'created'),
(1068, 6,  TIMESTAMP '2024-03-11 17:00:00', 'created'),
(1069, 7,  TIMESTAMP '2024-03-13 19:00:00', 'created'),
(1070, 8,  TIMESTAMP '2024-03-15 08:45:00', 'created'),
(1071, 9,  TIMESTAMP '2024-03-17 10:15:00', 'created'),
(1072, 10, TIMESTAMP '2024-03-19 11:45:00', 'created'),
(1073, 11, TIMESTAMP '2024-03-21 13:15:00', 'created'),
(1074, 12, TIMESTAMP '2024-03-23 15:00:00', 'created'),
(1075, 13, TIMESTAMP '2024-03-25 17:30:00', 'created'),
(1076, 14, TIMESTAMP '2024-03-27 19:15:00', 'created'),
(1077, 15, TIMESTAMP '2024-03-29 09:30:00', 'created'),
(1078, 16, TIMESTAMP '2024-03-31 11:00:00', 'created'),
(1079, 22, TIMESTAMP '2024-03-02 12:30:00', 'created'),
(1080, 23, TIMESTAMP '2024-03-04 14:00:00', 'created'),
(1081, 24, TIMESTAMP '2024-03-06 15:30:00', 'created'),
(1082, 25, TIMESTAMP '2024-03-08 17:00:00', 'created'),
(1083, 26, TIMESTAMP '2024-03-10 19:30:00', 'created'),
(1084, 17, TIMESTAMP '2024-03-12 20:00:00', 'created'),
(1085, 18, TIMESTAMP '2024-03-14 21:00:00', 'created'),
(1086, 19, TIMESTAMP '2024-03-16 22:00:00', 'created'),
(1087, 20, TIMESTAMP '2024-03-18 10:00:00', 'canceled'),
(1088, 21, TIMESTAMP '2024-03-20 11:30:00', 'created'),
(1089, 22, TIMESTAMP '2024-03-22 13:00:00', 'created'),
(1090, 23, TIMESTAMP '2024-03-24 14:30:00', 'created'),
(1091, 24, TIMESTAMP '2024-03-26 16:00:00', 'created'),
(1092, 25, TIMESTAMP '2024-03-28 18:00:00', 'created'),
-- Апрель
(1093, 1,  TIMESTAMP '2024-04-01 09:00:00', 'created'),
(1094, 2,  TIMESTAMP '2024-04-03 10:30:00', 'created'),
(1095, 3,  TIMESTAMP '2024-04-05 12:00:00', 'created'),
(1096, 4,  TIMESTAMP '2024-04-07 13:45:00', 'created'),
(1097, 5,  TIMESTAMP '2024-04-09 15:15:00', 'canceled'),
(1098, 6,  TIMESTAMP '2024-04-11 17:00:00', 'created'),
(1099, 7,  TIMESTAMP '2024-04-13 19:00:00', 'created'),
(1100, 8,  TIMESTAMP '2024-04-15 08:45:00', 'created'),
(1101, 9,  TIMESTAMP '2024-04-17 10:15:00', 'created'),
(1102, 10, TIMESTAMP '2024-04-19 11:45:00', 'created'),
(1103, 26, TIMESTAMP '2024-04-02 13:15:00', 'created'),
(1104, 27, TIMESTAMP '2024-04-04 15:00:00', 'created'),
(1105, 28, TIMESTAMP '2024-04-06 17:30:00', 'created'),
(1106, 29, TIMESTAMP '2024-04-08 19:15:00', 'created'),
(1107, 30, TIMESTAMP '2024-04-10 09:30:00', 'created'),
(1108, 1,  TIMESTAMP '2024-04-12 11:00:00', 'created'),
(1109, 2,  TIMESTAMP '2024-04-14 12:30:00', 'created'),
(1110, 3,  TIMESTAMP '2024-04-16 14:00:00', 'created'),
(1111, 4,  TIMESTAMP '2024-04-18 15:30:00', 'created'),
(1112, 5,  TIMESTAMP '2024-04-20 17:00:00', 'created'),
(1113, 6,  TIMESTAMP '2024-04-22 19:30:00', 'created'),
(1114, 7,  TIMESTAMP '2024-04-24 20:00:00', 'created'),
(1115, 8,  TIMESTAMP '2024-04-26 21:00:00', 'created'),
(1116, 9,  TIMESTAMP '2024-04-28 22:00:00', 'created'),
(1117, 10, TIMESTAMP '2024-04-30 10:00:00', 'created');
```

#### 2.3. Позиции заказов

```sql
INSERT INTO order_items (order_id, product_id, quantity) VALUES
(1001, 101, 1), (1002, 102, 2), (1003, 103, 3), (1004, 104, 1),
(1006, 105, 1), (1007, 106, 2), (1008, 101, 1), (1009, 103, 5),
(1010, 104, 2), (1011, 105, 1), (1012, 106, 3), (1014, 103, 2),
(1015, 101, 1), (1016, 102, 1), (1017, 104, 1), (1018, 105, 1),
(1019, 103, 4), (1020, 106, 1), (1021, 101, 1), (1022, 104, 1),
(1023, 105, 1), (1024, 104, 1), (1026, 106, 2), (1027, 107, 1),
(1028, 108, 1), (1029, 101, 1), (1030, 103, 2), (1031, 104, 1),
(1032, 105, 1),
(1033, 106, 1), (1034, 102, 2), (1036, 103, 3), (1037, 101, 1),
(1038, 104, 1), (1039, 102, 1), (1040, 105, 1), (1041, 106, 1),
(1042, 103, 2), (1043, 107, 1), (1044, 101, 1), (1045, 103, 2),
(1047, 104, 1), (1048, 105, 1), (1049, 106, 2), (1050, 108, 1),
(1051, 109, 1), (1052, 101, 1), (1053, 104, 1), (1054, 103, 3),
(1055, 105, 1), (1056, 106, 1), (1057, 102, 2), (1058, 107, 1),
(1059, 108, 1), (1060, 109, 2), (1061, 110, 3), (1062, 101, 1),
(1063, 101, 1), (1064, 103, 2), (1066, 104, 1), (1067, 105, 1),
(1068, 106, 2), (1069, 108, 1), (1070, 109, 1), (1071, 101, 1),
(1072, 104, 1), (1073, 103, 3), (1074, 105, 1), (1075, 106, 1),
(1076, 102, 2), (1077, 107, 1), (1078, 108, 1), (1079, 109, 2),
(1080, 110, 3), (1081, 101, 1), (1082, 104, 1), (1083, 103, 2),
(1084, 105, 1), (1085, 106, 1), (1086, 102, 2), (1088, 107, 1),
(1089, 108, 1), (1090, 109, 2), (1091, 110, 3), (1092, 101, 1),
(1093, 101, 1), (1094, 103, 2), (1095, 104, 1), (1096, 105, 1),
(1098, 106, 2), (1099, 108, 1), (1100, 109, 1), (1101, 101, 1),
(1102, 104, 1), (1103, 103, 3), (1104, 105, 1), (1105, 106, 1),
(1106, 102, 2), (1107, 107, 1), (1108, 108, 1), (1109, 109, 2),
(1110, 110, 3), (1111, 101, 1), (1112, 104, 1), (1113, 103, 2),
(1114, 105, 1), (1115, 106, 1), (1116, 102, 2), (1117, 107, 1);
```

#### 2.4. Действия пользователей

```sql
INSERT INTO user_actions (user_id, order_id, action, time)
SELECT user_id, order_id, 'create_order', creation_time
FROM orders;

INSERT INTO user_actions (user_id, order_id, action, time)
SELECT user_id, order_id, 'cancel_order', creation_time + INTERVAL '1 hour'
FROM orders
WHERE status = 'canceled';
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

> **Бизнес-смысл:** `date_trunc('week', ...)` в PostgreSQL начинает неделю с понедельника (ISO 8601). На 4 месяцах — около 18 недель.

### 3. MAU — по календарным месяцам

```sql
SELECT
    date_trunc('month', time)::date AS month,
    COUNT(DISTINCT user_id)         AS mau
FROM user_actions
GROUP BY date_trunc('month', time)
ORDER BY month;
```

> **Бизнес-смысл:** MAU показывает широту аудитории. На 4 месяцах данных — 4 строки.

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

### 6. Retention — базовый запрос (дни)

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
    MAX(CASE WHEN day_number = 14 THEN retention END) AS "14",
    MAX(CASE WHEN day_number = 30 THEN retention END) AS "30"
FROM retention r
JOIN cohort_size cs ON cs.start_date = r.start_date
GROUP BY date_trunc('month', r.start_date)::date, r.start_date, cs.cohort_size
ORDER BY r.start_date;
```

> **Бизнес-смысл:** матрица позволяет сравнивать когорты между собой. `cohort_size` — размер когорты. `day_number = 0` всегда `1.00`. `NULL` — данных за этот день ещё нет.

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
    MAX(CASE WHEN week_number = 7 THEN retention END) AS "w7"
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
    MAX(CASE WHEN month_number = 3 THEN retention END) AS "m3"
FROM retention r
JOIN cohort_size cs ON cs.start_date = r.start_date
GROUP BY date_trunc('month', r.start_date)::date, r.start_date, cs.cohort_size
ORDER BY r.start_date;
```

> **Бизнес-смысл:** месячная матрица — классический формат для отчётов по удержанию. На 4 месяцах данных — m0–m3.

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
- Работа с явно заданными данными — без генерации, всё воспроизводимо.
- Retention-матрицы в трёх разрезах (день, неделя, месяц) с колонкой `cohort_size`.
- Работа с продуктовыми метриками маркетплейса: DAU, WAU, MAU, ARPU, ARPPU, CR, retention.

## 🔗 Интерактивная демонстрация

[Открыть в SQLize.online — PostgreSQL](https://sqlize.online/sql/psql/)
