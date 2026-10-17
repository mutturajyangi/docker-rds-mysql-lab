# Architecture

## Startup sequence

1. Compose creates `frontend-net`, `backend-net` (internal) and the `mysql-data` volume.
2. `mysql` starts. If `mysql-data` is empty, the entrypoint creates the root user, the
   `inventory` database and the `app` user from `.env`, then runs `db/init/01-schema.sql`
   and `02-seed.sql` in alphabetical order.
3. The MySQL healthcheck (`mysqladmin ping`) runs every 5s. While init scripts are running, the
   server only listens on a socket, so the check keeps failing until MySQL is really ready.
4. When `mysql` reports `healthy`, Compose starts `api` and `phpmyadmin`
   (`depends_on: condition: service_healthy`).
5. `api` has its own `HEALTHCHECK` that calls `/health`, which runs `SELECT VERSION()`. A container
   that is `healthy` therefore proves the whole path from the app to the database works.

## Request flow

1. The client calls `localhost:8000/products`. Port 8000 is published from `api` on `frontend-net`.
2. FastAPI opens a connection to `mysql:3306`. The name resolves through Docker's embedded DNS
   because `api` is also attached to `backend-net`.
3. The query runs, the connection is committed (or rolled back on error) and closed, and JSON is returned.

phpMyAdmin follows the same path on port 8081. It is a web console, so it holds no credentials
of its own: the user logs in with a MySQL account.

## Networks

| Network        | `internal` | Members                     | Effect                                                    |
|----------------|------------|-----------------------------|-----------------------------------------------------------|
| `frontend-net` | no         | `api`, `phpmyadmin`         | Can publish ports to the host and reach the internet     |
| `backend-net`  | yes        | `mysql`, `api`, `phpmyadmin`| No host port mapping, no outbound internet               |

`mysql` is only on `backend-net`, so even if someone added a `ports:` mapping to it there
would be no route from the host. A container that joins only `frontend-net` can't even resolve
the name `mysql`. `scripts/check_isolation.sh` demonstrates all of this.

## Data lifecycle

| Command                      | Containers | Networks | `mysql-data` volume |
|------------------------------|------------|----------|---------------------|
| `docker compose stop`        | stopped    | kept     | kept                |
| `docker compose down`        | removed    | removed  | kept                |
| `docker compose down -v`     | removed    | removed  | **deleted**         |

`backup.sh` runs `mysqldump --single-transaction`, which gives a consistent InnoDB snapshot
without locking tables, so the API keeps serving while the backup runs. `restore.sh` pipes the
dump back into `mysql`. The dump includes `DROP TABLE IF EXISTS`, so restoring over a live
database replaces the tables.
