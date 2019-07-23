module Dynflow
  module Executors
    module Sidekiq
      module WorkerJobs
        class PerformWork < InternalJobBase
          def perform(work_item)
            Executors.run_user_code do
              work_item.world = Dynflow.process_world
              work_item.execute
            end
          rescue Errors::PersistenceError => e
            OrchestratorJobs::HandlePersistenceError.perform_async(e, work_item)
          ensure
            # TODO AJ: get telemetry back
            # Dynflow::Telemetry.with_instance { |t| t.increment_counter(:dynflow_worker_events, 1, @telemetry_options) }
            OrchestratorJobs::WorkerDone.perform_async(work_item)
          end
        end
      end
    end
  end
end
