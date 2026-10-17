"""Small inventory CRUD API backed by MySQL (the "application tier" of the RDS lab)."""
import os
from contextlib import contextmanager
from decimal import Decimal

import pymysql
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="Docker RDS Lab - Inventory API")

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "mysql"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "app"),
    "password": os.getenv("DB_PASSWORD", ""),
    "database": os.getenv("DB_NAME", "inventory"),
    "cursorclass": pymysql.cursors.DictCursor,
    "connect_timeout": 3,
}


@contextmanager
def db_cursor():
    """Open a connection, yield a cursor, commit on success and always close."""
    conn = pymysql.connect(**DB_CONFIG)
    try:
        with conn.cursor() as cur:
            yield cur
        conn.commit()
    finally:
        conn.close()


class ProductIn(BaseModel):
    name: str = Field(..., max_length=100)
    category: str = Field(..., max_length=50)
    price: Decimal = Field(..., ge=0, max_digits=10, decimal_places=2)
    stock: int = Field(0, ge=0)


class OrderIn(BaseModel):
    product_id: int
    quantity: int = Field(..., gt=0)


@app.get("/")
def root():
    return {"message": "Inventory API for the Docker RDS lab", "docs": "/docs"}


@app.get("/health")
def health():
    try:
        with db_cursor() as cur:
            cur.execute("SELECT VERSION() AS version")
            version = cur.fetchone()["version"]
    except pymysql.MySQLError as exc:
        raise HTTPException(status_code=503, detail=f"database unavailable: {exc}")
    return {"status": "ok", "db_host": DB_CONFIG["host"], "mysql_version": version}


@app.get("/products")
def list_products():
    with db_cursor() as cur:
        cur.execute("SELECT * FROM products ORDER BY id")
        return cur.fetchall()


@app.get("/products/{product_id}")
def get_product(product_id: int):
    with db_cursor() as cur:
        cur.execute("SELECT * FROM products WHERE id = %s", (product_id,))
        row = cur.fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="product not found")
    return row


@app.post("/products", status_code=201)
def create_product(product: ProductIn):
    with db_cursor() as cur:
        cur.execute(
            "INSERT INTO products (name, category, price, stock) VALUES (%s, %s, %s, %s)",
            (product.name, product.category, product.price, product.stock),
        )
        new_id = cur.lastrowid
        cur.execute("SELECT * FROM products WHERE id = %s", (new_id,))
        return cur.fetchone()


@app.delete("/products/{product_id}", status_code=204)
def delete_product(product_id: int):
    with db_cursor() as cur:
        cur.execute("DELETE FROM products WHERE id = %s", (product_id,))
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="product not found")


@app.get("/orders")
def list_orders():
    with db_cursor() as cur:
        cur.execute(
            """SELECT o.id, o.product_id, p.name AS product, o.quantity,
                      o.quantity * p.price AS total, o.ordered_at
               FROM orders o JOIN products p ON p.id = o.product_id
               ORDER BY o.id"""
        )
        return cur.fetchall()


@app.post("/orders", status_code=201)
def create_order(order: OrderIn):
    """Place an order and decrement stock in one transaction."""
    with db_cursor() as cur:
        cur.execute("SELECT stock FROM products WHERE id = %s FOR UPDATE", (order.product_id,))
        row = cur.fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="product not found")
        if row["stock"] < order.quantity:
            raise HTTPException(status_code=409, detail=f"only {row['stock']} in stock")
        cur.execute(
            "UPDATE products SET stock = stock - %s WHERE id = %s",
            (order.quantity, order.product_id),
        )
        cur.execute(
            "INSERT INTO orders (product_id, quantity) VALUES (%s, %s)",
            (order.product_id, order.quantity),
        )
        return {"id": cur.lastrowid, **order.model_dump()}
