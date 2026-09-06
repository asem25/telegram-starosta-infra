#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <mini-app-image> <mini-app-tag>" >&2
  exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
compose_file="${script_dir}/docker-compose.mini-app.yaml"
prod_env="${script_dir}/prod.env"
mini_app_image="$1"
mini_app_tag="$2"

if [[ ! -s "${prod_env}" ]]; then
  echo "Missing non-empty ${prod_env}. Create it from prod.mini-app.env.example." >&2
  exit 1
fi

compose=(docker compose --env-file "${prod_env}" -f "${compose_file}")
export PROD_ENV_FILE="${prod_env}"
export MINI_APP_IMAGE="${mini_app_image}"
export MINI_APP_TAG="${mini_app_tag}"

"${compose[@]}" config --quiet
"${compose[@]}" pull mini-app
"${compose[@]}" up -d --force-recreate mini-app

for ((attempt = 1; attempt <= 30; attempt++)); do
  container_id="$("${compose[@]}" ps -q mini-app)"
  status=""
  if [[ -n "${container_id}" ]]; then
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${container_id}" 2>/dev/null || true)"
  fi

  if [[ "${status}" == "healthy" ]]; then
    "${compose[@]}" ps
    docker image prune -f >/dev/null
    exit 0
  fi

  sleep 5
done

echo "mini-app did not become healthy" >&2
"${compose[@]}" logs --tail 100 mini-app >&2 || true
exit 1
