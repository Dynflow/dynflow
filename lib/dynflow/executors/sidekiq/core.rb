# frozen_string_literal: true

require 'dynflow/executors/sidekiq/serialization'
require 'dynflow/executors/sidekiq/internal_job_base'
require 'dynflow/executors/sidekiq/orchestrator_jobs'
require 'dynflow/executors/sidekiq/worker_jobs'
require 'dynflow/executors/sidekiq/redis_locking'

require 'sidekiq-reliable-fetch'
Sidekiq.configure_server do |config|
  # Use semi-reliable fetch
  # for details see https://gitlab.com/gitlab-org/sidekiq-reliable-fetch/blob/master/README.md
  config[:semi_reliable_fetch] = true
  Sidekiq::ReliableFetch.setup_reliable_fetch!(config)
end
::Sidekiq.strict_args!

module Dynflow
  module Executors
    module Sidekiq
      class Core < Abstract::Core
        include RedisLocking

        TELEMETRY_UPDATE_INTERVAL = 30 # update telemetry every 30s

        attr_reader :logger

        def initialize(world, *_args)
          @world = world
          @logger = world.logger
          wait_for_orchestrator_lock
          super
          schedule_update_telemetry
          begin_startup!
        end

        def heartbeat
          super
          reacquire_orchestrator_lock
        end

        def start_termination(*args)
          super
          release_orchestrator_lock
          finish_termination
        end

        # TODO: needs thoughs on how to implement it
        def execution_status(execution_plan_id = nil)
          {}
        end

        def feed_pool(work_items)
          work_items.each do |new_work|
            WorkerJobs::PerformWork.set(queue: suggest_queue(new_work)).perform_async(new_work)
          end
        end

        def update_telemetry
          sidekiq_queues = ::Sidekiq::Stats.new.queues
          @queues_options.keys.each do |queue|
            queue_size = sidekiq_queues[queue.to_s]
            if queue_size
              Dynflow::Telemetry.with_instance { |t| t.set_gauge(:dynflow_queue_size, queue_size, telemetry_options(queue)) }
            end
          end
          schedule_update_telemetry
        end

        def work_finished(work, delayed_events = nil)
          # If the work item is sent in reply to a request from the current orchestrator, proceed
          if work.sender_orchestrator_id == @world.id
            super
          else
            # If we're in recovery, we can drop the work as the execution plan will be resumed during validity checks performed when leaving recovery
            # If we're not in recovery and receive an event from another orchestrator, it means it survived the queue draining.
            handle_unknown_work_item(work) unless @recovery
          end
        end

        def begin_startup!
          WorkerJobs::DrainMarker.perform_async(@world.id)
          @recovery = true
        end

        def startup_complete
          logger.info('Performing validity checks')
          @world.perform_validity_checks
          logger.info('Finished performing validity checks')
          if @world.delayed_executor && !@world.delayed_executor.started?
            @world.delayed_executor.start
          end
          @recovery = false
        end

        private

        def fallback_queue
          :default
        end

        def schedule_update_telemetry
          @world.clock.ping(reference, TELEMETRY_UPDATE_INTERVAL, [:update_telemetry])
        end

        def telemetry_options(queue)
          { queue: queue.to_s, world: @world.id }
        end

        # We take a look if an execution lock is already being held by an orchestrator (it should be the current one). If no lock is held
        # we try to resume the execution plan if possible
        def handle_unknown_work_item(work)
          # We are past recovery now, if we receive an event here, the execution plan will be most likely paused
          # We can either try to rescue it or turn it over to stopped
          execution_lock = @world.coordinator.find_locks(class: Coordinator::ExecutionLock.name,
                                                         id: "execution-plan:#{work.execution_plan_id}").first
          if execution_lock.nil?
            plan = @world.persistence.load_execution_plan(work.execution_plan_id)
            should_resume = !plan.error? || plan.prepare_for_rescue == :running
            @world.execute(plan.id) if should_resume
          end
        end
      end
    end
  end
end
