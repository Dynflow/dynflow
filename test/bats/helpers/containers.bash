#!/usr/bin/env bash
# Container helper functions for bats tests

# Default container names
POSTGRES_CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-dynflow-test-postgres}"
REDIS_CONTAINER_NAME="${REDIS_CONTAINER_NAME:-dynflow-test-redis}"

# Default ports
POSTGRES_PORT="${POSTGRES_PORT:-15432}"
REDIS_PORT="${REDIS_PORT:-16379}"

# Database credentials
POSTGRES_USER="${POSTGRES_USER:-dynflow_test}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-dynflow_test_pass}"
POSTGRES_DB="${POSTGRES_DB:-dynflow_test}"

# Container images
POSTGRES_IMAGE="${POSTGRES_IMAGE:-docker.io/library/postgres:15}"
REDIS_IMAGE="${REDIS_IMAGE:-docker.io/library/redis:7-alpine}"

# Start PostgreSQL container
start_postgres() {
  echo "Starting PostgreSQL container: ${POSTGRES_CONTAINER_NAME}" >&2

  podman run -d \
    --name "${POSTGRES_CONTAINER_NAME}" \
    -e POSTGRES_USER="${POSTGRES_USER}" \
    -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
    -e POSTGRES_DB="${POSTGRES_DB}" \
    -p "${POSTGRES_PORT}:5432" \
    "${POSTGRES_IMAGE}" \
    postgres -c fsync=off -c synchronous_commit=off -c full_page_writes=off

  # Wait for PostgreSQL to be ready
  echo "Waiting for PostgreSQL to be ready..." >&2
  local max_attempts=30
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    if podman exec "${POSTGRES_CONTAINER_NAME}" pg_isready -U "${POSTGRES_USER}" > /dev/null 2>&1; then
      echo "PostgreSQL is ready" >&2
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  echo "ERROR: PostgreSQL failed to start within ${max_attempts} seconds" >&2
  return 1
}

stop_container() {
  local container="$1"
  local with_volumes="$2"

  echo "Stopping container: ${container}" >&2
  if podman ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
    podman stop -t 2 "${container}" > /dev/null 2>&1 || true
    if [ "$with_volumes" = "1" ]; then
        podman rm -v -f "${container}" > /dev/null 2>&1 || true
    else
        podman rm -f "${container}" > /dev/null 2>&1 || true
    fi
  fi
}

# Stop PostgreSQL container
stop_postgres() {
  stop_container "$POSTGRES_CONTAINER_NAME" "$1"
}

# Start Redis container
start_redis() {
  echo "Starting Redis container: ${REDIS_CONTAINER_NAME}" >&2

  podman run -d \
    --name "${REDIS_CONTAINER_NAME}" \
    -p "${REDIS_PORT}:6379" \
    "${REDIS_IMAGE}"

  # Wait for Redis to be ready
  echo "Waiting for Redis to be ready..." >&2
  local max_attempts=30
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    if podman exec "${REDIS_CONTAINER_NAME}" redis-cli ping > /dev/null 2>&1; then
      echo "Redis is ready" >&2
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  echo "ERROR: Redis failed to start within ${max_attempts} seconds" >&2
  return 1
}

# Stop Redis container
stop_redis() {
  stop_container "$REDIS_CONTAINER_NAME" "$1"
}

# Check if PostgreSQL container is running
is_postgres_running() {
  podman ps --format "{{.Names}}" | grep -q "^${POSTGRES_CONTAINER_NAME}$"
}

# Check if Redis container is running
is_redis_running() {
  podman ps --format "{{.Names}}" | grep -q "^${REDIS_CONTAINER_NAME}$"
}

# Get PostgreSQL connection string
get_postgres_url() {
  echo "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${POSTGRES_PORT}/${POSTGRES_DB}"
}

# Get Redis URL
get_redis_url() {
  echo "redis://localhost:${REDIS_PORT}/0"
}

# Execute SQL in PostgreSQL container
exec_sql() {
  local sql="$1"
  podman exec "${POSTGRES_CONTAINER_NAME}" \
    psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "${sql}"
}

# Execute Redis command
exec_redis() {
  podman exec "${REDIS_CONTAINER_NAME}" redis-cli "$@"
}

# Clean up all test containers
cleanup_containers() {
  stop_postgres 1
  stop_redis 1
}

# Start all test containers
start_containers() {
  start_postgres || return 1
  start_redis || return 1
}
