#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <backend-image> <backend-tag>" >&2
  exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
compose_file="${script_dir}/docker-compose.yaml"
prod_env="${script_dir}/prod.env"
backend_image="$1"
backend_tag="$2"

if [[ ! -s "${prod_env}" ]]; then
  echo "Missing non-empty ${prod_env}. Create it from prod.backend.env.example." >&2
  exit 1
fi

if grep -Eq '(^|=)replace-with-|example\.com' "${prod_env}"; then
  echo "${prod_env} still contains example placeholders" >&2
  exit 1
fi

required_keys=(
  POSTGRES_DB
  POSTGRES_USER
  POSTGRES_PASSWORD
  TELEGRAM_BOT_TOKEN
  TELEGRAM_AUTH_TOKEN_SECRET
  MINI_APP_ALLOWED_ORIGINS
  SEMESTER_START
  SEMESTER_END
)

for key in "${required_keys[@]}"; do
  if ! grep -Eq "^[[:space:]]*${key}=.+" "${prod_env}"; then
    echo "Missing required key ${key} in ${prod_env}" >&2
    exit 1
  fi
done

compose=(docker compose --env-file "${prod_env}" -f "${compose_file}")
export PROD_ENV_FILE="${prod_env}"
export BACKEND_IMAGE="${backend_image}"
export BACK_TAG="${backend_tag}"

wait_until_healthy() {
  local service="$1"
  local attempts="$2"
  local delay_seconds="$3"
  local container_id status

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    container_id="$("${compose[@]}" ps -q "${service}")"
    status=""
    if [[ -n "${container_id}" ]]; then
      status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${container_id}" 2>/dev/null || true)"
    fi

    if [[ "${status}" == "healthy" ]]; then
      return 0
    fi

    sleep "${delay_seconds}"
  done

  echo "${service} did not become healthy" >&2
  "${compose[@]}" logs --tail 100 "${service}" >&2 || true
  return 1
}

"${compose[@]}" config --quiet
"${compose[@]}" up -d postgres
wait_until_healthy postgres 30 3

"${compose[@]}" pull backend
"${compose[@]}" up -d --force-recreate backend
wait_until_healthy backend 360 5

"${compose[@]}" ps
docker image prune -f >/dev/null
