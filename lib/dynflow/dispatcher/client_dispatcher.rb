module Dynflow
  module Dispatcher
    class ClientDispatcher < Abstract

      TrackedRequest = Algebrick.type do
        fields! id: Integer, request: Request, accepted: Concurrent::IVar, finished: Concurrent::IVar
      end

      module TrackedRequest
        def accept!
          accepted.set true unless accepted.completed?
          self
        end

        def fail!(error)
          accepted.fail error unless accepted.completed?
          finished.fail error
          self
        end

        def success!(resolve_to)
          accepted.set true unless accepted.completed?
          finished.set(resolve_to)
          self
        end
      end

      def initialize(world)
        @world            = Type! world, World
        @last_id          = 0
        @tracked_requests = {}
        @terminated       = nil
      end

      def publish_request(future, request, timeout)
        track_request(future, request, timeout) do |tracked_request|
          dispatch_request(request, @world.id, tracked_request.id)
        end
      end

      def invalidate_allocation(allocation)
        plan = @world.persistence.load_execution_plan(allocation.execution_plan_id)
        plan.execution_history.add('terminate execution', allocation.world_id)
        plan.update_state(:paused) unless plan.state == :paused
        dispatch_request(Dispatcher::Execution[allocation.execution_plan_id],
                         allocation.client_world_id,
                         allocation.request_id)
      rescue Errors::PersistenceError
        log(Logger::ERROR, "failed to write data while invalidating allocation #{allocation}")
      end

      def timeout(request_id)
        resolve_tracked_request(request_id, Dynflow::Error.new("Request timeout"))
      end

      def start_termination(*args)
        super
        @tracked_requests.values.each { |tracked_request| tracked_request.fail!(Dynflow::Error.new('Dispatcher terminated')) }
        @tracked_requests.clear
        finish_termination
      end

      private

      def dispatch_request(request, client_world_id, request_id)
        executor_id = match request,
            (on ~Execution do |execution|
               AnyExecutor
             end),
            (on ~Event do |event|
               find_executor(event.execution_plan_id)
             end),
            (on Ping.(~any) do |receiver_id|
               receiver_id
             end)
        request = Envelope[request_id, client_world_id, executor_id, request]
        if Dispatcher::UnknownWorld === request.receiver_id
          raise Dynflow::Error, "Could not find an executor for #{request}"
        end
        connector.send(request).value!
      rescue => e
        respond(request, Failed[e.message])
      end

      def dispatch_response(envelope)
        return unless @tracked_requests.key?(envelope.request_id)
        match envelope.message,
            (on ~Accepted do
               @tracked_requests[envelope.request_id].accept!
             end),
            (on ~Failed do |msg|
               resolve_tracked_request(envelope.request_id, Dynflow::Error.new(msg.error))
             end),
            (on Done | Pong do
               resolve_tracked_request(envelope.request_id)
             end)
      end

      def find_executor(execution_plan_id)
        executor = @world.persistence.find_executor_for_plan(execution_plan_id)
        if executor
          executor.id
        else
          Dispatcher::UnknownWorld
        end
      end

      def track_request(finished, request, timeout)
        id = @last_id += 1
        tracked_request = TrackedRequest[id, request, Concurrent::IVar.new, finished]
        @tracked_requests[id] = tracked_request
        @world.clock.ping(self, timeout, [:timeout, id]) if timeout
        yield tracked_request
      rescue Dynflow::Error => e
        resolve_tracked_request(tracked_request.id, e)
        log(Logger::ERROR, e)
      end

      def reset_tracked_request(tracked_request)
        if tracked_request.finished.completed?
          raise Dynflow::Error.new('Can not reset resolved tracked request')
        end
        unless tracked_request.accepted.completed?
          tracked_request.accept! # otherwise nobody would set the accept future
        end
        @tracked_requests[tracked_request.id] = TrackedRequest[tracked_request.id, tracked_request.request, Concurrent::IVar.new, tracked_request.finished]
      end

      def resolve_tracked_request(id, error = nil)
        return unless @tracked_requests.key?(id)
        if error
          @tracked_requests.delete(id).fail! error
        else
          tracked_request = @tracked_requests[id]
          resolve_to = match tracked_request.request,
              (on Execution.(execution_plan_id: ~any) do |uuid|
                 @world.persistence.load_execution_plan(uuid)
               end),
              (on Event | Ping do
                 true
               end)
          @tracked_requests.delete(id).success! resolve_to
        end
      end

    end
  end
end
