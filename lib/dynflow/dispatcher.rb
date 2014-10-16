# -*- coding: utf-8 -*-
module Dynflow
  class Dispatcher < Concurrent::Actor::Context
    include Algebrick::Matching

    Job = Algebrick.type do
      Event = type do
        fields! execution_plan_id: String,
                step_id:           Fixnum,
                event:             Object
      end

      Execution = type do
        fields! execution_plan_id: String
      end

      variants Event, Execution
    end

    PublishJob = Algebrick.type do
      fields! future: Concurrent::IVar, job: Job
    end

    Request = Algebrick.type do
      variants Job
    end

    Response = Algebrick.type do
      variants Accepted = atom,
               Failed   = type { fields! error: String },
               Done     = atom
    end

    Envelope = Algebrick.type do
      fields! request_id: Integer,
              sender_id: String,
              receiver_id: type { variants String, AnyExecutor = atom },
              message: type { variants Request, Response }
    end

    module Event
      def to_hash
        super.update event: Base64.strict_encode64(Marshal.dump(event))
      end

      def self.product_from_hash(hash)
        super(hash.merge 'event' => Marshal.load(Base64.strict_decode64(hash.fetch('event'))))
      end
    end

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

    # TODO: DRY - common for more actors
    StartTerminating = Algebrick.type do
      fields! terminated: Concurrent::IVar
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
               dispatch_job(add_tracked_job(future, job))
            end),
            (on ~Envelope.(message: ~Request) do |envelope, request|
               perform_job(envelope, request)
             end),
            (on ~Envelope.(message: ~Response) do |envelope, response|
               dispatch_response(envelope, response)
             end),
            (on StartTerminating.(~any) do |terminated|
               @terminated = terminated
               try_to_terminate
             end)
    end

    def dispatch_job(tracked_job)
      executor_id = match tracked_job.job,
                          (on ~Execution do |execution|
                             AnyExecutor
                           end),
                          (on ~Event do |event|
                             find_executor(event.execution_plan_id).id
                           end)
      request      = Envelope[tracked_job.id, @world.id, executor_id, tracked_job.job]
      connector.send(request)
    rescue Dynflow::Error => e
      resolve_tracked_job(tracked_job.id, e)
      log(Logger::ERROR, e)
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

    def dispatch_response(envelope, response)
      return unless @tracked_jobs.key?(envelope.request_id)
      match response,
          (on ~Accepted do
             @tracked_jobs[envelope.request_id].accept!
           end),
          (on ~Failed do |msg|
             resolve_tracked_job(envelope.request_id, Dynflow::Error.new(msg.error))
           end),
          (on ~Done do
             resolve_tracked_job(envelope.request_id)
           end)
    end

    def allocate_executor(execution_plan_id)
      @world.persistence.save_executor_allocation(Persistence::ExecutorAllocation[@world.id, execution_plan_id])
    end

    def find_executor(execution_plan_id)
      @world.persistence.find_executor_for_plan(execution_plan_id) or
          raise Dynflow::Error, "Could not find an executor for execution plan #{ execution_plan_id }"
    end

    def add_tracked_job(finished, job)
      id = @last_id += 1
      tracked_job = TrackedJob[id, job, Concurrent::IVar.new, finished]
      @tracked_jobs[id] = tracked_job
      return tracked_job
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
        resolve_to = nil
        match tracked_job.job,
            (on Execution.(execution_plan_id: ~any) do |uuid|
               plan = @world.persistence.load_execution_plan(uuid)
               if plan.state == :paused && plan.execution_history.events.last.name == 'terminate execution'
                 # TODO: counter: we should not do it for ever
                 dispatch_job(reset_tracked_job(tracked_job))
               else
                 resolve_to = plan
               end
             end),
            (on Event do
               resolve_to = true
             end)
        @tracked_jobs.delete(id).success! resolve_to unless resolve_to.nil?
      end
    end

    def respond(request_envelope, response)
      response_envelope = build_response_envelope(request_envelope, response)
      connector.send(response_envelope)
    end

    def build_response_envelope(request_envelope, response)
      Envelope[request_envelope.request_id,
               @world.id,
               request_envelope.sender_id,
               response]
    end

  end
end
