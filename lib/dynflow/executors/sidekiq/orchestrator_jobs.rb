# frozen_string_literal: true

module Dynflow
  module Executors
    module Sidekiq
      module OrchestratorJobs
        # handles resposnes about finished work form the workers
        # or some event to handle on orchestrator side
        class WorkerDone < InternalJobBase
          sidekiq_options queue: :dynflow_orchestrator

          # @param request_envelope [Dispatcher::Request] - request to handle on orchestrator side
          #   usually to start new execution or to pass some event
          def perform(work_item, delayed_events = nil)
            # Usually the step is saved on the worker's side. However if sidekiq is shut down,
            #   then the step may not have been saved so we save it just to be sure
            if work_item.is_a?(Director::StepWorkItem) && work_item.step&.error&.exception_class == ::Sidekiq::Shutdown
              work_item.step.save
            end
            Dynflow.process_world.executor.core.tell([:work_finished, work_item, delayed_events])
          end
        end

        # handles setting up an event on orchestrator
        class PlanEvent < InternalJobBase
          sidekiq_options queue: :dynflow_orchestrator

          # @param event_envelope [Dispatcher::Event] - request to handle on orchestrator side
          #   usually to start new execution or to pass some event
          def perform(execution_plan_id, step_id, event, time)
            Dynflow.process_world.plan_event(execution_plan_id, step_id, event, time)
          end
        end

        class HandlePersistenceError < InternalJobBase
          sidekiq_options queue: :dynflow_orchestrator

          # @param request_envelope [Dispatcher::Request] - request to handle on orchestrator side
          #   usually to start new execution or to pass some event
          def perform(error, work_item)
            Dynflow.process_world.executor.core.tell([:handle_persistence_error, error, work_item])
          end
        end

        class StartupComplete < InternalJobBase
          sidekiq_options queue: :dynflow_orchestrator

          # @param request_envelope [Dispatcher::Request] - request to handle on orchestrator side
          #   usually to start new execution or to pass some event
          def perform(world_id)
            if Dynflow.process_world.id == world_id
              Dynflow.process_world.executor.core.tell([:startup_complete])
            else
              logger.warn("Received startup complete for a different world #{world_id}, discarding.")
            end
          end
        end
      end
    end
  end
end
