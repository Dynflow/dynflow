#!/usr/bin/env bash
# Common helper functions for bats tests

# Get the project root directory
get_project_root() {
  local dir="${BATS_TEST_DIRNAME}"
  while [ "${dir}" != "/" ]; do
    if [ -f "${dir}/dynflow.gemspec" ]; then
      echo "${dir}"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done
  echo "ERROR: Could not find project root" >&2
  return 1
}

# Setup test environment variables
setup_test_env() {
  export PROJECT_ROOT="$(get_project_root)"
  export BUNDLE_GEMFILE="${PROJECT_ROOT}/Gemfile"

  # Set database URLs for tests
  export DATABASE_URL="$(get_postgres_url)"
  export REDIS_URL="$(get_redis_url)"
  export DB_CONN_STRING="$DATABASE_URL"

  # Test directories
  export TEST_PIDDIR="${BATS_TEST_TMPDIR}/pids"
}

run_background() {
  local label="$1"
  shift

  local log_file="$(bg_output_file "$label")"
  mkdir -p "$TEST_PIDDIR"
  (
      "$@" 2>&1 &
      echo $! >"${TEST_PIDDIR}/${label}.pid"
  ) | tee "$log_file" | sed "s/^/${label}: /" &
}

bg_output_file() {
    local label="$1"

    echo "${BATS_TEST_TMPDIR}/${label}.log"
}

# A function that polls a given command until it succeeds or until it runs out
wait_for() {
  local timeout="$1"
  local interval="$2"
  shift 2

  local elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  echo "Timeout after ${timeout}s waiting for: $*" >&2
  return 1
}
