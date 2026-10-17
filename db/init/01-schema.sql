-- Runs automatically on the first start (empty mysql-data volume).
USE inventory;

CREATE TABLE IF NOT EXISTS products (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(100)  NOT NULL,
    category    VARCHAR(50)   NOT NULL,
    price       DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    stock       INT           NOT NULL DEFAULT 0 CHECK (stock >= 0),
    created_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS orders (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    product_id  INT       NOT NULL,
    quantity    INT       NOT NULL CHECK (quantity > 0),
    ordered_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_orders_product FOREIGN KEY (product_id)
        REFERENCES products(id) ON DELETE CASCADE
);
