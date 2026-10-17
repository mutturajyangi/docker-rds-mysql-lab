#!/usr/bin/env bash
# Show that MySQL lives in a private network (like an RDS instance in a private subnet).
set -uo pipefail
cd "$(dirname "$0")/.."

echo "1) From the host -> localhost:3306"
if timeout 2 bash -c '</dev/tcp/127.0.0.1/3306' 2>/dev/null; then
  echo "   REACHABLE (something on the host is using 3306; it is not this lab's MySQL)"
else
  echo "   BLOCKED: mysql publishes no port"
fi

echo "2) From the api container (on backend-net) -> mysql:3306"
docker compose exec -T api python -c \
  "import socket; socket.create_connection(('mysql', 3306), 2); print('   ALLOWED: api can reach the database')"

echo "3) From a throwaway container on frontend-net only -> mysql:3306"
docker run --rm --network rds-lab_frontend-net busybox:1.36 \
  sh -c 'nc -z -w 2 mysql 3306 && echo "   REACHABLE (unexpected)" || echo "   BLOCKED: mysql is not on frontend-net"'

echo "4) From the mysql container -> the internet"
docker compose exec -T mysql sh -c \
  'timeout 3 bash -c "</dev/tcp/1.1.1.1/443" 2>/dev/null && echo "   REACHABLE (unexpected)" || echo "   BLOCKED: backend-net is internal (no NAT gateway)"'
