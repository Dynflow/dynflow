module Dynflow
  module Dispatcher
    class ExecutorDispatcher < Abstract
      def initialize(world, semaphore)
        @world           = Type! world, World
        @current_futures = Set.new
      end

      def handle_request(envelope)
        match(envelope.message,
              on(Execution) { perform_execution(envelope, envelope.message) },
              on(Event)     { perform_event(envelope, envelope.message) })
      end

      protected

      def perform_execution(envelope, execution)
        allocate_executor(execution.execution_plan_id, envelope.sender_id, envelope.request_id)
        execution_lock = Coordinator::ExecutionLock.new(@world, execution.execution_plan_id, envelope.sender_id, envelope.request_id)
        future = on_finish do |f|
          f.then do |plan|
            when_done(plan, envelope, execution, execution_lock)
          end.rescue do |reason|
            @world.coordinator.release(execution_lock)
            respond(envelope, Failed[reason.to_s])
          end
        end
        @world.executor.execute(execution.execution_plan_id, future)
        respond(envelope, Accepted)
      rescue Dynflow::Error => e
        future.fail(e) if future && !future.completed?
        respond(envelope, Failed[e.message])
      end

      def when_done(plan, envelope, execution, execution_lock)
        if plan.state == :running
          @world.invalidate_execution_lock(execution_lock)
        else
          @world.coordinator.release(execution_lock)
          respond(envelope, Done)
        end
      end

      def perform_event(envelope, event_request)
        future = on_finish do |f|
          f.then do
            respond(envelope, Done)
          end.rescue do |reason|
            respond(envelope, Failed[reason.to_s])
          end
        end
        @world.executor.event(event_request.execution_plan_id, event_request.step_id, event_request.event, future)
      rescue Dynflow::Error => e
        future.fail(e) if future && !future.completed?
      end

      def start_termination(*args)
        super
        if @current_futures.empty?
          reference.tell(:finish_termination)
        else
          Concurrent.zip(*@current_futures).then { reference.tell(:finish_termination) }
        end
      end

      private

      def allocate_executor(execution_plan_id, client_world_id, request_id)
        execution_lock = Coordinator::ExecutionLock.new(@world, execution_plan_id, client_world_id, request_id)
        @world.coordinator.acquire(execution_lock)
      end

      def on_finish
        raise "Dispatcher terminating: no new work can be started" if terminating?
        future = Concurrent.future
        callbacks_future = (yield future).rescue { |reason| @world.logger.error("Unexpected fail on future #{reason}") }
        # we track currently running futures to make sure to not
        # terminate until the execution is finished (including
        # cleaning of locks etc)
        @current_futures << callbacks_future
        callbacks_future.on_completion! { reference.tell([:finish_execution, callbacks_future]) }
        return future
      end

      def finish_execution(future)
        @current_futures.delete(future)
      end
    end
  end
end
