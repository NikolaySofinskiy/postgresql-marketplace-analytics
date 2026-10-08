-- ============================================
-- PostgreSQL Marketplace Analytics
-- ============================================

-- 1. СОЗДАНИЕ ТАБЛИЦ
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

-- 2. ИНДЕКСЫ
CREATE INDEX idx_orders_dt     ON orders(order_dt);
CREATE INDEX idx_orders_seller ON orders(seller_id);
CREATE INDEX idx_orders_region ON orders(region);
CREATE INDEX idx_orders_user   ON orders(user_id);
CREATE INDEX idx_sellers_city  ON sellers(city_id);
CREATE INDEX idx_users_city    ON users(city_id);