require 'dynflow/executors/sidekiq/serialization'
require 'dynflow/executors/sidekiq/internal_job_base'
require 'dynflow/executors/sidekiq/orchestrator_jobs'
require 'dynflow/executors/sidekiq/worker_jobs'

module Dynflow
  module Executors
    module Sidekiq
      class Core < Abstract::Core
        attr_reader :logger

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

        private

        def fallback_queue
          :default
        end
      end
    end
  end
end
