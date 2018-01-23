module Dynflow
  module Dispatcher
    class ClientDispatcher < Abstract

      TrackedRequest = Algebrick.type do
        fields! id: Integer, request: Request,
                accepted: Concurrent::Edge::Future, finished: Concurrent::Edge::Future
      end

      module TrackedRequest
        def accept!
          accepted.success true unless accepted.completed?
          self
        end

        def fail!(error)
          accepted.fail error unless accepted.completed?
          finished.fail error
          self
        end

        def success!(resolve_to)
          accepted.success true unless accepted.completed?
          finished.success(resolve_to)
          self
        end
      end

      class PingCache
        TIME_FORMAT = '%Y-%m-%d %H:%M:%S.%L'
        PING_CACHE_AGE = 10

        def self.format_time(time = Time.now)
          time.strftime(TIME_FORMAT)
        end

        def self.load_time(time)
          Time.strptime(time, TIME_FORMAT)
        end

        def initialize(world)
          @world = world
        end

        def add_record(id, time = Time.now)
          record = find_world id
          record.data[:meta].update(:last_seen => self.class.format_time(time))
          @world.coordinator.update_record(record)
        end

        def fresh_record?(id)
          record = find_world(id)
          return false if record.nil?
          time = self.class.load_time(record.data[:meta][:last_seen])
          time >= Time.now - PING_CACHE_AGE
        end

        private

        def find_world(id)
          @world.coordinator.find_records(:id => id,
                                          :class => ['Dynflow::Coordinator::ExecutorWorld', 'Dynflow::Coordinator::ClientWorld']).first
        end
      end

      attr_reader :ping_cache
      def initialize(world)
        @world            = Type! world, World
        @last_id          = 0
        @tracked_requests = {}
        @terminated       = nil
        @ping_cache       = PingCache.new world
      end

      def publish_request(future, request, timeout)
        with_ping_request_caching(request, future) do
          track_request(future, request, timeout) do |tracked_request|
            dispatch_request(request, @world.id, tracked_request.id)
          end
        end
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

      def dispatch_request(request, client_world_id, request_id)
        executor_id = match request,
                            (on ~Execution do |execution|
                               AnyExecutor
                             end),
                            (on ~Event do |event|
                               find_executor(event.execution_plan_id)
                             end),
                            (on Ping.(~any) | Status.(~any, ~any) do |receiver_id, _|
                               receiver_id
                             end)
        envelope = Envelope[request_id, client_world_id, executor_id, request]
        if Dispatcher::UnknownWorld === envelope.receiver_id
          raise Dynflow::Error, "Could not find an executor for #{envelope}"
        end
        connector.send(envelope).value!
      rescue => e
        log(Logger::ERROR, e)
        respond(envelope, Failed[e.message]) if envelope
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
              (on Done do
                 resolve_tracked_request(envelope.request_id)
               end),
              (on Pong do
                 add_ping_cache_record(envelope.sender_id)
                 resolve_tracked_request(envelope.request_id)
               end),
              (on ExecutionStatus.(~any) do |steps|
                 @tracked_requests.delete(envelope.request_id).success! steps
               end)
      end

      def add_ping_cache_record(id)
        log Logger::DEBUG, "adding ping cache record for #{id}"
        @ping_cache.add_record id
      end

      private

      def find_executor(execution_plan_id)
        execution_lock = @world.coordinator.find_locks(class: Coordinator::ExecutionLock.name,
                                                       id: "execution-plan:#{execution_plan_id}").first
        if execution_lock
          execution_lock.world_id
        else
          Dispatcher::UnknownWorld
        end
      rescue => e
        log(Logger::ERROR, e)
        Dispatcher::UnknownWorld
      end

      def track_request(finished, request, timeout)
        id = @last_id += 1
        tracked_request = TrackedRequest[id, request, Concurrent.future, finished]
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
        @tracked_requests[tracked_request.id] = TrackedRequest[tracked_request.id, tracked_request.request, Concurrent.future, tracked_request.finished]
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

      def with_ping_request_caching(request, future)
        if request.is_a?(Dynflow::Dispatcher::Ping) && @ping_cache.fresh_record?(request.receiver_id)
          future.success true
          future
        else
          yield
        end
      end
    end
  end
end
