#!/usr/bin/env bats
# Example bats test file for Dynflow

# Load helper functions
load helpers/containers
load helpers/common

# Setup runs before each test
setup() {
  # Setup environment variables
  setup_test_env

  # Ensure containers are running
  if ! is_postgres_running; then
    start_postgres
  fi
  if ! is_redis_running; then
    start_redis
  fi
}

# Teardown runs after each test
teardown() {
    (
        cd "$TEST_PIDDIR"
        for pidfile in $(ls -1 .); do
            kill -15 $(cat "$pidfile")
        done
    )
    rm -rf "$TEST_TMPDIR"
}

@test "only one orchestrator can be active at a time" {
    cd "$(get_project_root)"

    run_background 'o1' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
    wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "${TEST_TMPDIR}/o1.log"

    run_background 'o2' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
    wait_for 30 1 grep 'dynflow: Orchestrator lock already taken, entering passive mode.' "${TEST_TMPDIR}/o2.log"
}

@test "multiple orchestrators can be active with multiple redis dbs" {
    cd "$(get_project_root)"

    run_background 'o1' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
    wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "${TEST_TMPDIR}/o1.log"

    export REDIS_URL=${REDIS_URL%/0}/1
    run_background 'o2' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
    wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "${TEST_TMPDIR}/o1.log"
}

@test "orchestrators do fail over" {
    cd "$(get_project_root)"

    run_background 'o1' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
    wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "${TEST_TMPDIR}/o1.log"

    run_background 'o2' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
    wait_for 30 1 grep 'dynflow: Orchestrator lock already taken, entering passive mode.' "${TEST_TMPDIR}/o2.log"

    kill -15 "$(cat "$TEST_PIDDIR/o1.pid")"
    wait_for 120 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "${TEST_TMPDIR}/o2.log"
}
