#!/bin/bash
set -euxo pipefail

echo "Starting postgres..."
docker compose up -d postgres

for i in {1..50}; do
  s=$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q postgres)" 2>/dev/null || echo "")
  echo "Postgres health: $s"
  [ "$s" = "healthy" ] && break
  sleep 3
done

if [ "$s" != "healthy" ]; then
  echo "Postgres is not healthy"
  docker compose logs postgres
  exit 1
fi

echo "Starting backend..."
docker compose up -d --no-deps --pull always --force-recreate backend

for i in {1..50}; do
  s=$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q backend)" 2>/dev/null || echo "")
  echo "Backend health: $s"
  [ "$s" = "healthy" ] && break
  sleep 3
done

if [ "$s" != "healthy" ]; then
  echo "Backend is not healthy"
  docker compose logs backend
  exit 1
fi

echo "Starting frontend..."
docker compose up -d --pull always --force-recreate frontend

echo "Final containers:"
docker compose ps

docker image prune -af || true