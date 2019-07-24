module Dynflow
  module Executors
    module Sidekiq
      module WorkerJobs
        class PerformWork < InternalJobBase
          def perform(work_item)
            with_telemetry(work_item) do
              Executors.run_user_code do
                if work_item.is_a? Director::StepWorkItem
                  step = world.persistence.load_step(work_item.step.execution_plan_id,
                                                     work_item.step.id,
                                                     world)
                  work_item.step = step
                  # Return if the step is already done, but the response was not sent
                  # to the orchestrator
                  return if [:success, :skipped, :error].include? step.state
                end
                work_item.world = world
                work_item.execute
              end
            end
          rescue Errors::PersistenceError => e
            OrchestratorJobs::HandlePersistenceError.perform_async(e, work_item)
          ensure
            OrchestratorJobs::WorkerDone.perform_async(work_item)
          end

          private

          def world
            Dynflow.process_world
          end

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
      end
    end
  end
end
