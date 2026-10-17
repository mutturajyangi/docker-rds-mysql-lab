#!/usr/bin/env bash
# Smoke test: health, create a product, read it, order it, delete it.
# Usage: ./scripts/test_api.sh [base_url]
set -euo pipefail
BASE="${1:-http://localhost:8000}"

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

step "Health"
curl -fsS "$BASE/health"; echo

step "Create a product"
created=$(curl -fsS -X POST "$BASE/products" -H 'Content-Type: application/json' \
  -d '{"name":"Smoke Test Widget","category":"Test","price":9.99,"stock":10}')
echo "$created"
id=$(echo "$created" | sed -E 's/.*"id":([0-9]+).*/\1/')

step "Read it back (id=$id)"
curl -fsS "$BASE/products/$id"; echo

step "Order 3 of them (stock should drop to 7)"
curl -fsS -X POST "$BASE/orders" -H 'Content-Type: application/json' \
  -d "{\"product_id\":$id,\"quantity\":3}"; echo
curl -fsS "$BASE/products/$id"; echo

step "Order 100 (should be rejected with 409)"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/orders" -H 'Content-Type: application/json' \
  -d "{\"product_id\":$id,\"quantity\":100}")
echo "HTTP $code"; [[ "$code" == 409 ]]

step "Delete it"
code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$BASE/products/$id")
echo "HTTP $code"; [[ "$code" == 204 ]]

printf '\n\033[32mAll checks passed.\033[0m\n'
