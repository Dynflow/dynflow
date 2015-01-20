module Dynflow
  module Dispatcher
    class ExecutorDispatcher < Concurrent::Actor::Context
      include Algebrick::Matching

      def initialize(world)
        @world        = Type! world, World
      end

      private

      def on_message(message)
        match message,
            (on ~Envelope.(message: Ping) do |envelope|
               respond(envelope, Pong)
             end),
            (on ~Envelope.(message: ~Request) do |envelope, request|
               perform_job(envelope, request)
             end)
      end

      def perform_job(envelope, job)
        future = Concurrent::IVar.new.with_observer do |_, value, reason|
          if Execution === job
            allocation = Persistence::ExecutorAllocation[@world.id, job.execution_plan_id]
            @world.persistence.delete_executor_allocation(allocation)
          end
          if reason
            respond(envelope, Failed[reason.message])
          else
            respond(envelope, Done)
          end
        end
        match job,
            (on ~Execution do |(execution_plan_id)|
               allocate_executor(job.execution_plan_id)
               @world.executor.execute(execution_plan_id, future)
             end),
            (on ~Event do |(execution_plan_id, step_id, event)|
               @world.executor.event(execution_plan_id, step_id, event, future)
             end)
        respond(envelope, Accepted)
      rescue Dynflow::Error => e
        respond(envelope, Failed[e.message])
      end

      def allocate_executor(execution_plan_id)
        @world.persistence.save_executor_allocation(Persistence::ExecutorAllocation[@world.id, execution_plan_id])
      end

      def find_executor(execution_plan_id)
        @world.persistence.find_executor_for_plan(execution_plan_id) or
            raise Dynflow::Error, "Could not find an executor for execution plan #{ execution_plan_id }"
      end

      def respond(request_envelope, response)
        response_envelope = build_response_envelope(request_envelope, response)
        @world.connector.send(response_envelope)
      end

      def build_response_envelope(request_envelope, response)
        Envelope[request_envelope.request_id,
                 @world.id,
                 request_envelope.sender_id,
                 response]
      end

    end
  end
end
