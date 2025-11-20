#!/usr/bin/env bash
# Suite-level teardown - runs once after all tests

# Load container helpers
source "$(dirname "${BASH_SOURCE[0]}")/helpers/containers.bash"

# This function runs once after all tests in the suite
teardown_suite() {
  echo "=== Tearing down bats test suite ===" >&2

  # Clean up all test containers
  echo "Cleaning up test containers..." >&2
  cleanup_containers

  echo "=== Test suite teardown complete ===" >&2
}
