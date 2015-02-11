module Dynflow
  module Dispatcher
    class ExecutorDispatcher < Abstract
      def initialize(world)
        @world        = Type! world, World
      end

      def handle_request(envelope)
        match(envelope.message,
              on(Execution) { perform_execution(envelope, envelope.message) },
              on(Event)     { perform_event(envelope, envelope.message) })
      end

      private

      def perform_execution(envelope, execution)
        future = Concurrent::IVar.new.with_observer do |_, plan, reason|
          allocation = Persistence::ExecutorAllocation[@world.id, execution.execution_plan_id, envelope.sender_id, envelope.request_id]
          @world.persistence.delete_executor_allocation(allocation)
          if plan && plan.state == :running
            @world.client_dispatcher.tell([:invalidate_allocation, allocation])
          elsif reason
            respond(envelope, Failed[reason.message])
          else
            respond(envelope, Done)
          end
        end
        allocate_executor(execution.execution_plan_id, envelope.sender_id, envelope.request_id)
        @world.executor.execute(execution.execution_plan_id, future)
        respond(envelope, Accepted)
      rescue Dynflow::Error => e
        respond(envelope, Failed[e.message])
      end

      def perform_event(envelope, event_job)
        future = Concurrent::IVar.new.with_observer do |_, _, reason|
          if reason
            respond(envelope, Failed[reason.message])
          else
            respond(envelope, Done)
          end
        end
        @world.executor.event(event_job.execution_plan_id, event_job.step_id, event_job.event, future)
      end

      def allocate_executor(execution_plan_id, client_world_id, request_id)
        @world.persistence.save_executor_allocation(Persistence::ExecutorAllocation[@world.id, execution_plan_id, client_world_id, request_id])
      end

      def find_executor(execution_plan_id)
        @world.persistence.find_executor_for_plan(execution_plan_id) or
            raise Dynflow::Error, "Could not find an executor for execution plan #{ execution_plan_id }"
      end
    end
  end
end
