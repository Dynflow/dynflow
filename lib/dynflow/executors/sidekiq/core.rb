require 'dynflow/executors/sidekiq/serialization'
require 'dynflow/executors/sidekiq/internal_job_base'
require 'dynflow/executors/sidekiq/orchestrator_jobs'
require 'dynflow/executors/sidekiq/worker_jobs'

module Dynflow
  module Executors
    module Sidekiq
      class Core < Abstract::Core
        TELEMETRY_UPDATE_INTERVAL = 30 # update telemetry every 30s

        attr_reader :logger

        def initialize(*_args)
          super
          schedule_update_telemetry
        end

        def start_termination(*args)
          super
          # nothing extra to terminate in Sidekiq executor
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
