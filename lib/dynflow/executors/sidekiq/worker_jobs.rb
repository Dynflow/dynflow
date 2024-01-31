# frozen_string_literal: true

module Dynflow
  module Executors
    module Sidekiq
      module WorkerJobs
        class PerformWork < InternalJobBase
          def perform(work_item)
            with_telemetry(work_item) do
              Executors.run_user_code do
                work_item.world = Dynflow.process_world
                work_item.execute
              end
            end
          rescue Errors::PersistenceError => e
            OrchestratorJobs::HandlePersistenceError.perform_async(e, work_item)
          ensure
            step = work_item.step if work_item.is_a?(Director::StepWorkItem)
            OrchestratorJobs::WorkerDone.perform_async(work_item, step && step.delayed_events)
          end

          private

          def with_telemetry(work_item)
            Dynflow::Telemetry.with_instance { |t| t.set_gauge(:dynflow_active_workers, +1, telemetry_options(work_item)) }
            yield
          ensure
            Dynflow::Telemetry.with_instance do |t|
              t.increment_counter(:dynflow_worker_events, 1, telemetry_options(work_item))
              t.set_gauge(:dynflow_active_workers, -1, telemetry_options(work_item))
            end
          end
        end

        class DrainMarker < InternalJobBase
          def perform(world_id)
            OrchestratorJobs::StartupComplete.perform_async(world_id)
          end
        end
      end
    end
  end
end
