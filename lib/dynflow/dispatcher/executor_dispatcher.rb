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
              on(Event)     { perform_event(envelope, envelope.message) },
              on(Status)    { get_execution_status(envelope, envelope.message) })
      end

      protected

      def perform_execution(envelope, execution)
        allocate_executor(execution.execution_plan_id, envelope.sender_id, envelope.request_id)
        execution_lock = Coordinator::ExecutionLock.new(@world, execution.execution_plan_id, envelope.sender_id, envelope.request_id)
        future = on_finish do |f|
          f.then do |plan|
            when_done(plan, envelope, execution, execution_lock)
          end.rescue do |reason|
            # TODO AJ: the coorinator would be needed only in cases when there are multiple
            # orchestrators - we might not need them at all, if we stick to the
            # one orchestrator per deployment.
            @world.coordinator.release(execution_lock)
            # TODO AJ: DEAD get rid of all the code handling the responses
            # respond(envelope, Failed[reason.to_s])
          end
        end
        @world.executor.execute(execution.execution_plan_id, future)
        # TODO AJ: DEAD
        # respond(envelope, Accepted)
      rescue Dynflow::Error => e
        future.reject(e) if future && !future.resolved?
        # TODO AJ: DEAD
        # respond(envelope, Failed[e.message])
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
        # TODO AJ: DEAD
        # future = on_finish do |f|
        #   f.then do
        #     respond(envelope, Done)
        #   end.rescue do |reason|
        #     respond(envelope, Failed[reason.to_s])
        #   end
        # end
        @world.executor.event(event_request.execution_plan_id, event_request.step_id, event_request.event)
      rescue Dynflow::Error => e
        # TODO AJ: log the error
        # TODO AJ: DEAD
        # future.reject(e) if future && !future.resolved?
      end

      def start_termination(*args)
        super
        if @current_futures.empty?
          reference.tell(:finish_termination)
        else
          Concurrent::Promises.zip_futures(*@current_futures).then { reference.tell(:finish_termination) }
        end
      end

      def get_execution_status(envelope, envelope_message)
        # TODO AJ: figure out how to get the execution status without using responses, e.g.
        # via updating the world registry with current values
        raise NotImplementedError
        # TODO AJ: DEAD
        # items = @world.executor.execution_status envelope_message.execution_plan_id
        # respond(envelope, ExecutionStatus[execution_status: items])
      end

      private

      def allocate_executor(execution_plan_id, client_world_id, request_id)
        execution_lock = Coordinator::ExecutionLock.new(@world, execution_plan_id, client_world_id, request_id)
        @world.coordinator.acquire(execution_lock)
      end

      def on_finish
        raise "Dispatcher terminating: no new work can be started" if terminating?
        future = Concurrent::Promises.resolvable_future
        callbacks_future = (yield future).rescue { |reason| @world.logger.error("Unexpected fail on future #{reason}") }
        # we track currently running futures to make sure to not
        # terminate until the execution is finished (including
        # cleaning of locks etc)
        @current_futures << callbacks_future
        callbacks_future.on_resolution! { reference.tell([:finish_execution, callbacks_future]) }
        return future
      end

      def finish_execution(future)
        @current_futures.delete(future)
      end
    end
  end
end
