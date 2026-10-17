# Docker RDS Lab: MySQL + phpMyAdmin + API

Simulating an **AWS RDS for MySQL** deployment with nothing but Docker Compose.

A MySQL database runs on a **private network with no published port**, like an RDS instance
in a private subnet. A FastAPI inventory API (the application tier) and phpMyAdmin (the
console) are the only ways in. Passwords live in a gitignored `.env`, data lives on a named
volume, and two scripts take and restore snapshots.

```
                 ┌──────────────── frontend-net ("public subnet") ────────────────┐
  Browser ─:8000─▶  api (FastAPI, /docs)                                          │
  Browser ─:8081─▶  phpmyadmin                                                    │
                 └────────┬──────────────────────────────┬──────────────────────┘
                 ┌────────▼──────────────────────────────▼─ backend-net (internal: true) ─┐
                 │                 mysql:8.4   (no published port)                         │
                 │                 └── volume: mysql-data                                  │
                 └────────────────────────────────────────────────────────────────────────┘
```

## AWS ↔ Docker mapping

| AWS concept                              | This lab                                                         |
|------------------------------------------|------------------------------------------------------------------|
| RDS for MySQL instance                   | `mysql` container (official `mysql:8.4` image)                   |
| DB in a private subnet                   | `backend-net` with `internal: true`, no host port for MySQL      |
| No NAT gateway on the DB subnet          | `internal: true` also blocks outbound internet from MySQL        |
| Security group (only the app → 3306)     | Only `api` and `phpmyadmin` are attached to `backend-net`        |
| Public subnet / ALB-facing app           | `frontend-net`, where `api` and `phpmyadmin` publish ports       |
| Secrets Manager                          | `.env` (gitignored); the repo ships only `.env.example`          |
| EBS storage                              | Named volume `mysql-data`                                        |
| Restore from snapshot into a new DB      | `db/init/*.sql` seeds an empty volume on first start             |
| Manual snapshot / restore                | `scripts/backup.sh` / `scripts/restore.sh` (`mysqldump`)         |
| RDS status "available"                   | MySQL healthcheck + `depends_on: condition: service_healthy`     |
| RDS Query Editor                         | phpMyAdmin                                                       |

## Project structure

```
.
├── api/
│   ├── main.py              # FastAPI CRUD: /products, /orders, /health
│   ├── requirements.txt
│   ├── Dockerfile           # Non-root user, HEALTHCHECK
│   └── .dockerignore
├── db/init/
│   ├── 01-schema.sql        # products + orders tables (FK, CHECK constraints)
│   └── 02-seed.sql          # Sample data
├── scripts/
│   ├── test_api.sh          # End-to-end smoke test of the API
│   ├── check_isolation.sh   # Proves the DB is only reachable from the backend network
│   ├── backup.sh            # mysqldump -> backups/*.sql.gz
│   └── restore.sh           # Restore the latest (or a given) backup
├── docs/
│   └── architecture.md
├── backups/                 # Backup files land here (gitignored)
├── .env.example
└── docker-compose.yml
```

## Prerequisites

- Docker Engine 20.10+ with the Compose v2 plugin (`docker compose version`)
- `curl` and `gzip` (for the scripts)

## Run it

```bash
# 1. Create your secrets file and change the passwords
cp .env.example .env

# 2. Start everything. The API and phpMyAdmin wait until MySQL is healthy.
docker compose up -d --build

# 3. Check status
docker compose ps
# NAME         STATUS                    PORTS
# api          Up (healthy)              0.0.0.0:8000->8000/tcp
# mysql        Up (healthy)
# phpmyadmin   Up                        0.0.0.0:8081->80/tcp
```

| What           | URL                          | Login                                          |
|----------------|------------------------------|------------------------------------------------|
| API (Swagger)  | <http://localhost:8000/docs> | none                                           |
| phpMyAdmin     | <http://localhost:8081>      | `MYSQL_USER` / `MYSQL_PASSWORD` from `.env`    |

Note that MySQL has no row in this table. That's the point.

## Demos

### 1. Use the API and watch the data in phpMyAdmin

```bash
curl http://localhost:8000/products
curl -X POST http://localhost:8000/products -H 'Content-Type: application/json' \
     -d '{"name":"Webcam","category":"Peripherals","price":59.00,"stock":15}'
```
Open phpMyAdmin → `inventory` → `products` and the new row is there.
Edit a row in phpMyAdmin and `curl` it again to see the change from the API side.

Or run the full smoke test:
```bash
./scripts/test_api.sh
# == Health
# {"status":"ok","db_host":"mysql","mysql_version":"8.4.11"}
# == Create a product
# {"id":6,"name":"Smoke Test Widget","category":"Test","price":9.99,"stock":10,...}
# == Order 3 of them (stock should drop to 7)
# ...
# == Order 100 (should be rejected with 409)
# HTTP 409
# == Delete it
# HTTP 204
# All checks passed.
```
`POST /orders` locks the product row (`SELECT ... FOR UPDATE`), checks stock, decrements it and
inserts the order in **one transaction**, so stock can never go negative.

### 2. Network isolation (private subnet + security group)

```bash
./scripts/check_isolation.sh
# 1) From the host -> localhost:3306
#    BLOCKED: mysql publishes no port
# 2) From the api container (on backend-net) -> mysql:3306
#    ALLOWED: api can reach the database
# 3) From a throwaway container on frontend-net only -> mysql:3306
#    BLOCKED: mysql is not on frontend-net
# 4) From the mysql container -> the internet
#    BLOCKED: backend-net is internal (no NAT gateway)
```

### 3. Persistence (EBS volume)

```bash
docker compose down            # removes containers and networks, keeps the volume
docker compose up -d --wait
curl http://localhost:8000/products   # your data is still there

docker compose down -v         # -v also deletes the volume = terminate the DB without a final snapshot
```
After `down -v`, the next `up` sees an empty volume and re-runs `db/init/*.sql`, so you're back to the seed data.

### 4. Snapshot and restore

```bash
./scripts/backup.sh
# Backup written to backups/inventory-20261017-132858.sql.gz (4.0K)

# Simulate an accident
docker compose exec mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" inventory -e "DROP TABLE orders; DROP TABLE products;"'
curl http://localhost:8000/products     # 500: table doesn't exist

./scripts/restore.sh                    # restores the latest backup (or pass a file)
curl http://localhost:8000/products     # back
```

## Things worth noticing

- **`depends_on: condition: service_healthy`.** A plain `depends_on` only waits for the
  container to *start*. MySQL takes 10 to 20 seconds to be ready on first boot, and without the
  healthcheck the API would crash-loop on connection errors.
- **`${MYSQL_PASSWORD:?set it in .env}`.** Compose refuses to start if a secret is missing,
  instead of silently using an empty password.
- **MySQL 8 auth.** The default `caching_sha2_password` plugin needs the `cryptography` package in
  PyMySQL. Without it you get `RuntimeError: 'cryptography' package is required`.
- **Backups don't leak passwords.** The scripts read the password inside the container
  (`MYSQL_PWD="$MYSQL_ROOT_PASSWORD"`), so it never shows up in the host's process list or shell history.
- **Init scripts run once.** `db/init` is only executed when the data volume is empty. Changing
  `02-seed.sql` has no effect until you `down -v`.

## Clean up

```bash
docker compose down -v     # containers, networks and the data volume
docker rmi rds-lab-api     # the API image
```

See [docs/architecture.md](docs/architecture.md) for the startup sequence and request flow.

---

<sub>AI-ASSISTED · Built with help from an AI assistant (Claude) · Requires human review before use.</sub>
