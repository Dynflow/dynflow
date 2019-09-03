# frozen_string_literal: true
require 'dynflow/executors/sidekiq/serialization'
require 'dynflow/executors/sidekiq/internal_job_base'
require 'dynflow/executors/sidekiq/orchestrator_jobs'
require 'dynflow/executors/sidekiq/worker_jobs'
require 'dynflow/executors/sidekiq/redis_locking'

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
      end
    end
  end
end
