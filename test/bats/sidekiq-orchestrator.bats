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

@test "sanity" {
  cd "$(get_project_root)"

  run_background 'o1' bundle exec sidekiq -c 1 -r ./examples/remote_executor.rb -q dynflow_orchestrator
  wait_for 5 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o1)"

  run_background 'w1' bundle exec sidekiq -r ./examples/remote_executor.rb -q default
  wait_for 5 1 grep -P 'class=Dynflow::Executors::Sidekiq::WorkerJobs::DrainMarker.*INFO: done' "$(bg_output_file w1)"

  timeout 10 bundle exec ruby examples/remote_executor.rb client 1
  wait_for 1 1 grep -P 'dynflow: ExecutionPlan.*running >>.*stopped' "$(bg_output_file o1)"
}

@test "only one orchestrator can be active at a time" {
  cd "$(get_project_root)"

  run_background 'o1' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator -c 1
  wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o1)"

  run_background 'o2' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator -c 1
  wait_for 30 1 grep 'dynflow: Orchestrator lock already taken, entering passive mode.' "$(bg_output_file o2)"
}

@test "multiple orchestrators can be active with multiple redis dbs" {
  cd "$(get_project_root)"

  run_background 'o1' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator -c 1
  wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o1)"

  run_background 'w1' bundle exec sidekiq -r ./examples/remote_executor.rb -q default

  export REDIS_URL=${REDIS_URL%/0}/1
  run_background 'o2' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator -c 1
  wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o2)"

  run_background 'w2' bundle exec sidekiq -r ./examples/remote_executor.rb -q default

  # The client performs a round robin between the available executors
  # This should lead to each orchestrator handling one execution plan
  timeout 60 bundle exec ruby examples/remote_executor.rb client 2
  wait_for 1 1 grep -P 'dynflow: ExecutionPlan.*running >>.*stopped' "$(bg_output_file o1)"
  wait_for 1 1 grep -P 'dynflow: ExecutionPlan.*running >>.*stopped' "$(bg_output_file o2)"
}

@test "orchestrators do fail over" {
  cd "$(get_project_root)"

  run_background 'o1' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator -c 1
  wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o1)"

  run_background 'o2' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator -c 1
  wait_for 30 1 grep 'dynflow: Orchestrator lock already taken, entering passive mode.' "$(bg_output_file o2)"

  kill -15 "$(cat "$TEST_PIDDIR/o1.pid")"
  wait_for 120 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o2)"
}

@test "active orchestrator exits when pg goes away for good" {
  cd "$(get_project_root)"

  run_background 'o1' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator -c 1
  wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o1)"

  run_background 'w1' bundle exec sidekiq -r ./examples/remote_executor.rb -q default
  wait_for 5 1 grep 'dynflow: Finished performing validity checks' "$(bg_output_file o1)"

  podman stop "$POSTGRES_CONTAINER_NAME"
  wait_for 60 1 grep 'dynflow: World terminated, exiting.' "$(bg_output_file o1)"
}

@test "active orchestrator can withstand temporary pg connection drop" {
  cd "$(get_project_root)"

  run_background 'o1' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator -c 1
  wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o1)"

  run_background 'w1' bundle exec sidekiq -r ./examples/remote_executor.rb -q default
  wait_for 5 1 grep 'dynflow: Finished performing validity checks' "$(bg_output_file o1)"

  podman stop "$POSTGRES_CONTAINER_NAME"
  wait_for 30 1 grep 'dynflow: Persistence retry no. 1' "$(bg_output_file o1)"
  podman start "$POSTGRES_CONTAINER_NAME"
  wait_for 30 1 grep 'dynflow: Executor heartbeat' "$(bg_output_file o1)"

  timeout 30 bundle exec ruby examples/remote_executor.rb client 1
  wait_for 1 1 grep -P 'dynflow: ExecutionPlan.*running >>.*stopped' "$(bg_output_file o1)"
}

@test "active orchestrator can survive a brief redis connection drop" {
  cd "$(get_project_root)"

  run_background 'o1' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator -c 1
  wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o1)"

  run_background 'w1' bundle exec sidekiq -r ./examples/remote_executor.rb -q default
  wait_for 5 1 grep 'dynflow: Finished performing validity checks' "$(bg_output_file o1)"

  stop_redis
  wait_for 30 1 grep 'Error connecting to Redis' "$(bg_output_file o1)"
  start_redis

  timeout 10 bundle exec ruby examples/remote_executor.rb client 1
  wait_for 1 1 grep -P 'dynflow: ExecutionPlan.*running >>.*stopped' "$(bg_output_file o1)"
}

@test "active orchestrator can survive a longer redis connection drop" {
  cd "$(get_project_root)"

  run_background 'o1' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator -c 1
  wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o1)"

  run_background 'w1' bundle exec sidekiq -r ./examples/remote_executor.rb -q default
  wait_for 5 1 grep 'dynflow: Finished performing validity checks' "$(bg_output_file o1)"

  stop_redis 1
  wait_for 30 1 grep 'Error connecting to Redis' "$(bg_output_file o1)"
  start_redis

  wait_for 30 1 grep 'The orchestrator lock was lost, reacquired' "$(bg_output_file o1)"

  timeout 10 bundle exec ruby examples/remote_executor.rb client 1
  wait_for 1 1 grep -P 'dynflow: ExecutionPlan.*running >>.*stopped' "$(bg_output_file o1)"
}

@test "orchestrators can fail over if active one goes away during downtime" {
  cd "$(get_project_root)"

  run_background 'o1' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator -c 1
  wait_for 30 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o1)"

  run_background 'o2' bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator -c 1
  wait_for 30 1 grep 'dynflow: Orchestrator lock already taken, entering passive mode.' "$(bg_output_file o2)"

  run_background 'w1' bundle exec sidekiq -r ./examples/remote_executor.rb -q default
  wait_for 5 1 grep 'dynflow: Finished performing validity checks' "$(bg_output_file o1)"

  stop_redis 1
  wait_for 30 1 grep 'Error connecting to Redis' "$(bg_output_file o1)"
  kill -15 "$(cat "$TEST_PIDDIR/o1.pid")"
  start_redis

  wait_for 120 1 grep 'dynflow: Acquired orchestrator lock, entering active mode.' "$(bg_output_file o2)"
  wait_for 120 1 grep 'dynflow: Finished performing validity checks' "$(bg_output_file o2)"

  timeout 10 bundle exec ruby examples/remote_executor.rb client 1
  wait_for 1 1 grep -P 'dynflow: ExecutionPlan.*running >>.*stopped' "$(bg_output_file o2)"
}
