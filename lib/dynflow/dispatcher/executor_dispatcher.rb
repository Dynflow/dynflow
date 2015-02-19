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
          execution_lock = Coordinator::ExecutionLock.new(@world, execution.execution_plan_id, envelope.sender_id, envelope.request_id)
          if plan && plan.state == :running
            @world.invalidate_execution_lock(execution_lock)
          else
            @world.coordinator.release(execution_lock)
            if reason
              respond(envelope, Failed[reason.message])
            else
              respond(envelope, Done)
            end
          end
        end
        allocate_executor(execution.execution_plan_id, envelope.sender_id, envelope.request_id)
        @world.executor.execute(execution.execution_plan_id, future)
        respond(envelope, Accepted)
      rescue Dynflow::Error => e
        respond(envelope, Failed[e.message])
      end

      def perform_event(envelope, event_request)
        future = Concurrent::IVar.new.with_observer do |_, _, reason|
          if reason
            respond(envelope, Failed[reason.message])
          else
            respond(envelope, Done)
          end
        end
        @world.executor.event(event_request.execution_plan_id, event_request.step_id, event_request.event, future)
      end

      def allocate_executor(execution_plan_id, client_world_id, request_id)
        execution_lock = Coordinator::ExecutionLock.new(@world, execution_plan_id, client_world_id, request_id)
        @world.coordinator.acquire(execution_lock)
      end
    end
  end
end
