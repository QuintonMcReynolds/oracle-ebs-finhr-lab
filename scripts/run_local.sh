#!/usr/bin/env bash
# Spin up Oracle Database Free in Docker, install the lab, and run the tests.
# Used by both CI pipelines and for local runs:  ./scripts/run_local.sh
set -euo pipefail

IMAGE="gvenzl/oracle-free:23-slim-faststart"
NAME="ebs-finhr-lab-db"
APP_PW="${APP_USER_PASSWORD:-LabPassw0rd}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p 1521:1521 \
  -e ORACLE_PASSWORD="$APP_PW" \
  -e APP_USER=ebslab -e APP_USER_PASSWORD="$APP_PW" \
  "$IMAGE" >/dev/null

echo "Waiting for database..."
for i in $(seq 1 90); do
  if docker logs "$NAME" 2>&1 | grep -q "DATABASE IS READY TO USE"; then break; fi
  sleep 5
  if [ "$i" -eq 90 ]; then echo "Database did not start"; docker logs "$NAME"; exit 1; fi
done

docker cp "$ROOT" "$NAME":/tmp/lab
docker exec -w /tmp/lab "$NAME" bash -c \
  "sqlplus -S -L ebslab/$APP_PW@//localhost:1521/FREEPDB1 @install.sql </dev/null && \
   sqlplus -S -L ebslab/$APP_PW@//localhost:1521/FREEPDB1 @tests/run_tests.sql </dev/null"

[ "${KEEP_DB:-0}" = "1" ] || docker rm -f "$NAME" >/dev/null
