#!/usr/bin/env bash
# Suite-level setup - runs once before all tests

# Load container helpers
source "$(dirname "${BASH_SOURCE[0]}")/helpers/containers.bash"
source "$(dirname "${BASH_SOURCE[0]}")/helpers/common.bash"

# This function runs once before all tests in the suite
setup_suite() {
  echo "=== Setting up bats test suite ===" >&2

  # Verify podman is available
  if ! command -v podman &> /dev/null; then
    echo "ERROR: podman is not installed or not in PATH" >&2
    exit 1
  fi

  # Check if bundle is available
  PROJECT_ROOT="$(get_project_root)"
  if ! command -v bundle &> /dev/null; then
    echo "WARNING: bundler is not installed" >&2
  else
    # Install dependencies if needed
    echo "Checking bundle dependencies..." >&2
    cd "${PROJECT_ROOT}" && bundle check > /dev/null 2>&1 || bundle install
  fi

  # Pull container images if not already present
  echo "Checking container images..." >&2

  if ! podman image exists "${POSTGRES_IMAGE}"; then
    echo "Pulling PostgreSQL image: ${POSTGRES_IMAGE}" >&2
    podman pull "${POSTGRES_IMAGE}"
  fi

  if ! podman image exists "${REDIS_IMAGE}"; then
    echo "Pulling Redis image: ${REDIS_IMAGE}" >&2
    podman pull "${REDIS_IMAGE}"
  fi

  # Clean up any existing test containers from previous runs
  echo "Cleaning up any existing test containers..." >&2
  cleanup_containers

  echo "=== Test suite setup complete ===" >&2
}
