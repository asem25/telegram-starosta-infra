#!/usr/bin/env bash
set -euo pipefail
cd /ru/asem/bot/telegram-starosta-infra

docker compose config >/dev/null

# postgres -> backend -> frontend из за нехватки ресурсов
docker compose up -d postgres
for i in {1..50}; do
  s=$(docker inspect -f '{{.State.Health.Status}}' $(docker compose ps -q postgres) 2>/dev/null || echo "")
  [ "$s" = "healthy" ] && break
  sleep 3
done

docker compose up -d --no-deps --pull always --force-recreate backend
for i in {1..50}; do
  s=$(docker inspect -f '{{.State.Health.Status}}' $(docker compose ps -q backend) 2>/dev/null || echo "")
  [ "$s" = "healthy" ] && break
  sleep 3
done

docker compose up -d --no-deps --pull always --force-recreate frontend

docker image prune -af || true
