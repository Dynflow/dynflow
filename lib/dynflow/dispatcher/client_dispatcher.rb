module Dynflow
  module Dispatcher
    class ClientDispatcher < Concurrent::Actor::Context
      include Algebrick::Matching

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

      private

      def connector
        @world.connector
      end

      def try_to_terminate
        @tracked_jobs.values.each { |tracked_job| tracked_job.fail!(Dynflow::Error.new('Dispatcher terminated')) }
        @tracked_jobs.clear
        @terminated.set true
        reference.ask(:terminate!)
      end

      def on_message(message)
        match message,
            (on PublishJob.(~any, ~any) do |future, job|
               track_job(future, job) do |tracked_job|
                 dispatch_job(job, @world.id, tracked_job.id)
               end
             end),
            (on RePublishJob.(~any, ~any, ~any) do |job, client_world_id, request_id|
               dispatch_job(job, client_world_id, request_id)
             end),
            (on ~Envelope.(message: ~Response) do |envelope, response|
               dispatch_response(envelope, response)
             end),
            (on StartTerminating.(~any) do |terminated|
               @terminated = terminated
               try_to_terminate
             end)
      end

      def dispatch_job(job, client_world_id, request_id)
        executor_id = match job,
            (on ~Execution do |execution|
               AnyExecutor
             end),
            (on ~Event do |event|
               find_executor(event.execution_plan_id).id
             end),
            (on Ping.(~any) do |receiver_id|
               receiver_id
             end)
        request = Envelope[request_id, client_world_id, executor_id, job]
        connector.send(request)
      end

      def dispatch_response(envelope, response)
        return unless @tracked_jobs.key?(envelope.request_id)
        match response,
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
        @world.persistence.find_executor_for_plan(execution_plan_id) or
            raise Dynflow::Error, "Could not find an executor for execution plan #{ execution_plan_id }"
      end

      def track_job(finished, job)
        id = @last_id += 1
        tracked_job = TrackedJob[id, job, Concurrent::IVar.new, finished]
        @tracked_jobs[id] = tracked_job
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
