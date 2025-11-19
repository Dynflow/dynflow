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
  is_postgres_running && stop_postgres
  start_postgres
  is_redis_running && stop_redis
  start_redis
}

# Teardown runs after each test
teardown() {
    (
        cd "$TEST_PIDDIR" || return 1
        shopt -s nullglob
        for pidfile in * ; do
            kill -15 "$(cat "$pidfile")"
        done
    )
    cleanup_containers 1
}

@test "only one orchestrator can be active at a time" {
    cd "$(get_project_root)"

    run_background 'o1' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
    wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o1)"

    run_background 'o2' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
    wait_for 30 1 grep 'dynflow: Orchestrator lock already taken, entering passive mode.' "$(bg_output_file o2)"
}

@test "multiple orchestrators can be active with multiple redis dbs" {
    cd "$(get_project_root)"

    run_background 'o1' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
    wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o1)"

    export REDIS_URL=${REDIS_URL%/0}/1
    run_background 'o2' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
    wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o1)"
}

@test "orchestrators do fail over" {
    cd "$(get_project_root)"

    run_background 'o1' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
    wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o1)"

    run_background 'o2' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
    wait_for 30 1 grep 'dynflow: Orchestrator lock already taken, entering passive mode.' "$(bg_output_file o2)"

    kill -15 "$(cat "$TEST_PIDDIR/o1.pid")"
    wait_for 120 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o2)"
}
