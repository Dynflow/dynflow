module Dynflow
  module Dispatcher
    class ClientDispatcher < Abstract

      TrackedJob = Algebrick.type do
        fields! id: Integer, job: Job, accepted: Concurrent::IVar, finished: Concurrent::IVar
      end

      module TrackedJob
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
        @world        = Type! world, World
        @last_id      = 0
        @tracked_jobs = {}
        @terminated   = nil
      end

      def publish_job(future, job, timeout)
        track_job(future, job, timeout) do |tracked_job|
          dispatch_job(job, @world.id, tracked_job.id)
        end
      end

      def invalidate_allocation(allocation)
        plan = @world.persistence.load_execution_plan(allocation.execution_plan_id)
        plan.execution_history.add('terminate execution', allocation.world_id)
        plan.update_state(:paused) unless plan.state == :paused
        dispatch_job(Dispatcher::Execution[allocation.execution_plan_id],
                     allocation.client_world_id,
                     allocation.request_id)
      rescue Errors::PersistenceError
        log(Logger::ERROR, "failed to write data while invalidating allocation #{allocation}")
      end

      def timeout(request_id)
        resolve_tracked_job(request_id, Dynflow::Error.new("Request timeout"))
      end

      def start_termination(*args)
        super
        @tracked_jobs.values.each { |tracked_job| tracked_job.fail!(Dynflow::Error.new('Dispatcher terminated')) }
        @tracked_jobs.clear
        finish_termination
      end

      private

      def dispatch_job(job, client_world_id, request_id)
        executor_id = match job,
            (on ~Execution do |execution|
               AnyExecutor
             end),
            (on ~Event do |event|
               find_executor(event.execution_plan_id)
             end),
            (on Ping.(~any) do |receiver_id|
               receiver_id
             end)
        request = Envelope[request_id, client_world_id, executor_id, job]
        if Dispatcher::UnknownWorld === request.receiver_id
          raise Dynflow::Error, "Could not find an executor for #{job}"
        end
        connector.send(request).value!
      rescue => e
        respond(request, Failed[e.message])
      end

      def dispatch_response(envelope)
        return unless @tracked_jobs.key?(envelope.request_id)
        match envelope.message,
            (on ~Accepted do
               @tracked_jobs[envelope.request_id].accept!
             end),
            (on ~Failed do |msg|
               resolve_tracked_job(envelope.request_id, Dynflow::Error.new(msg.error))
             end),
            (on Done | Pong do
               resolve_tracked_job(envelope.request_id)
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

      def track_job(finished, job, timeout)
        id = @last_id += 1
        tracked_job = TrackedJob[id, job, Concurrent::IVar.new, finished]
        @tracked_jobs[id] = tracked_job
        @world.clock.ping(self, timeout, [:timeout, id]) if timeout
        yield tracked_job
      rescue Dynflow::Error => e
        resolve_tracked_job(tracked_job.id, e)
        log(Logger::ERROR, e)
      end

      def reset_tracked_job(tracked_job)
        if tracked_job.finished.completed?
          raise Dynflow::Error.new('Can not reset resolved tracked job')
        end
        unless tracked_job.accepted.completed?
          tracked_job.accept! # otherwise nobody would set the accept future
        end
        @tracked_jobs[tracked_job.id] = TrackedJob[tracked_job.id, tracked_job.job, Concurrent::IVar.new, tracked_job.finished]
      end

      def resolve_tracked_job(id, error = nil)
        return unless @tracked_jobs.key?(id)
        if error
          @tracked_jobs.delete(id).fail! error
        else
          tracked_job = @tracked_jobs[id]
          resolve_to = match tracked_job.job,
              (on Execution.(execution_plan_id: ~any) do |uuid|
                 @world.persistence.load_execution_plan(uuid)
               end),
              (on Event | Ping do
                 true
               end)
          @tracked_jobs.delete(id).success! resolve_to
        end
      end

    end
  end
end
