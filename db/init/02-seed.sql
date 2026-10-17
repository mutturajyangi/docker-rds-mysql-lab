USE inventory;

INSERT INTO products (name, category, price, stock) VALUES
    ('Mechanical Keyboard', 'Peripherals', 89.99, 25),
    ('Wireless Mouse',      'Peripherals', 29.50, 60),
    ('27" Monitor',         'Displays',   249.00, 12),
    ('USB-C Dock',          'Accessories', 119.00, 18),
    ('Laptop Stand',        'Accessories', 39.99, 40);

INSERT INTO orders (product_id, quantity) VALUES
    (1, 2), (2, 5), (3, 1), (2, 3), (5, 4);
