# -*- coding: utf-8 -*-
module Dynflow
  class World
    include Algebrick::TypeCheck
    include Algebrick::Matching

    attr_reader :id, :client_dispatcher, :executor_dispatcher, :executor, :connector,
        :persistence, :transaction_adapter, :action_classes, :subscription_index, :logger_adapter,
                :middleware, :auto_rescue

    def initialize(config)
      @id                  = UUIDTools::UUID.random_create.to_s
      config_for_world     = Config::ForWorld.new(config, self)
      config_for_world.validate
      @logger_adapter      = config_for_world.logger_adapter
      @transaction_adapter = config_for_world.transaction_adapter
      @persistence         = Persistence.new(self, config_for_world.persistence_adapter)
      @executor            = config_for_world.executor
      @action_classes      = config_for_world.action_classes
      @auto_rescue         = config_for_world.auto_rescue
      @connector           = config_for_world.connector
      @middleware          = Middleware::World.new
      @client_dispatcher   = Dispatcher::ClientDispatcher.spawn("client-dispatcher", self)
      calculate_subscription_index

      if executor
        @executor_dispatcher = Dispatcher::ExecutorDispatcher.spawn("executor-dispatcher", self)
        executor.initialized.wait
      end
      persistence.save_world(registered_world)
      @termination_barrier = Mutex.new

      at_exit { self.terminate.wait } if config_for_world.auto_terminate
      self.consistency_check if config_for_world.consistency_check
      self.execute_planned_execution_plans if config_for_world.auto_execute
    end

    def registered_world
      Persistence::RegisteredWorld[id, !!executor]
    end

    def clock
      @clock ||= Clock.spawn 'clock'
    end

    def logger
      logger_adapter.dynflow_logger
    end

    def action_logger
      logger_adapter.action_logger
    end

    def subscribed_actions(action_class)
      @subscription_index.has_key?(action_class) ? @subscription_index[action_class] : []
    end

    # reload actions classes, intended only for devel
    def reload!
      @action_classes.map! { |klass| klass.to_s.constantize }
      middleware.clear_cache!
      calculate_subscription_index
    end

    TriggerResult = Algebrick.type do
      # Returned by #trigger when planning fails.
      PlaningFailed   = type { fields! execution_plan_id: String, error: Exception }
      # Returned by #trigger when planning is successful but execution fails to start.
      ExecutionFailed = type { fields! execution_plan_id: String, error: Exception }
      # Returned by #trigger when planning is successful, #future will resolve after
      # ExecutionPlan is executed.
      Triggered       = type { fields! execution_plan_id: String, future: Concurrent::IVar }

      variants PlaningFailed, ExecutionFailed, Triggered
    end

    module TriggerResult
      def planned?
        match self, PlaningFailed => false, ExecutionFailed => true, Triggered => true
      end

      def triggered?
        match self, PlaningFailed => false, ExecutionFailed => false, Triggered => true
      end

      def id
        execution_plan_id
      end
    end

    module Triggered
      def finished
        future
      end
    end

    # @return [TriggerResult]
    # blocks until action_class is planned
    def trigger(action_class, *args)
      execution_plan = plan(action_class, *args)
      planned        = execution_plan.state == :planned

      if planned
        begin
          accepted = Concurrent::IVar.new
          done = execute(execution_plan.id, Concurrent::IVar.new, accepted)
          if accepted.wait.fulfilled?
            Triggered[execution_plan.id, done]
          else
            ExecutionFailed[execution_plan.id, accepted.reason]
          end
        rescue => exception
          ExecutionFailed[execution_plan.id, exception]
        end
      else
        PlaningFailed[execution_plan.id, execution_plan.errors.first.exception]
      end
    end

    def require_executor!
      raise 'Operation not permitted on a world without assigned executor' unless executor
    end

    def plan(action_class, *args)
      ExecutionPlan.new(self).tap do |execution_plan|
        execution_plan.prepare(action_class)
        execution_plan.plan(*args)
      end
    end

    # @return [Concurrent::IVar] containing execution_plan when finished
    # raises when ExecutionPlan is not accepted for execution
    def execute(execution_plan_id, done = Concurrent::IVar.new, accepted = Concurrent::IVar.new)
      publish_job(Dispatcher::Execution[execution_plan_id], done, accepted)
    end

    def event(execution_plan_id, step_id, event, done = Concurrent::IVar.new, accepted = Concurrent::IVar.new)
      publish_job(Dispatcher::Event[execution_plan_id, step_id, event], done, accepted)
    end

    def ping(world_id, done = Concurrent::IVar.new, accepted = Concurrent::IVar.new)
      publish_job(Dispatcher::Ping[world_id], done, accepted)
    end

    def publish_job(job, done, accepted)
      accepted.with_observer do |_, value, reason|
        done.fail reason if reason
      end
      client_dispatcher.ask(Dispatcher::PublishJob[done, job], accepted)
      done
    end

    def receive(envelope)
      match(envelope,
            (on Dispatcher::Envelope.(message: Dispatcher::Request) do
               executor_dispatcher << envelope
             end),
            (on Dispatcher::Envelope.(message: Dispatcher::Response) do
               client_dispatcher << envelope
             end))
    end

    def terminate(future = Concurrent::IVar.new)
      @termination_barrier.synchronize do
        @terminated ||= Concurrent::Promise.execute do
          # TODO: refactory once we can chain futures (probably after migrating
          #       to concurrent-ruby promises
          persistence.delete_world(registered_world)
          client_dispatcher_terminated = Concurrent::IVar.new
          logger.info "stop listening for new events..."
          listening_stopped     = connector.stop_listening(self)
          logger.info "start terminating client dispatcher..."
          client_dispatcher.ask(Dispatcher::StartTerminating[client_dispatcher_terminated])
          [client_dispatcher_terminated, listening_stopped].each(&:wait)

          if executor
            logger.info "start terminating executor..."
            executor.terminate.wait

            logger.info "start terminating executor dispatcher..."
            executor_dispatcher.ask(:terminate!).wait
          end

          if @clock
            logger.info "start terminating clock..."
            clock.ask(:terminate!).wait
          end

          connector.terminate
        end
      end

      @terminated.then { future.set true }
      future
    end

    # Detects execution plans that are marked as running but no executor
    # handles them (probably result of non-standard executor termination)
    #
    # The current implementation expects no execution_plan being actually run
    # by the executor.
    #
    # TODO: persist the running executors in the system, so that we can detect
    # the orphaned execution plans. The register should be managable by the
    # console, so that the administrator can unregister dead executors when needed.
    # After the executor is unregistered, the consistency check should be performed
    # to fix the orphaned plans as well.
    def consistency_check
      abnormal_execution_plans =
          self.persistence.find_execution_plans filters: { 'state' => %w(planning running) }
      if abnormal_execution_plans.empty?
        logger.info 'Clean start.'
      else
        format_str = '%36s %10s %10s'
        message    = ['Abnormal execution plans, process was probably killed.',
                      'Following ExecutionPlans will be set to paused, ',
                      'it should be fixed manually by administrator.',
                      (format format_str, 'ExecutionPlan', 'state', 'result'),
                      *(abnormal_execution_plans.map do |ep|
                        format format_str, ep.id, ep.state, ep.result
                      end)]

        logger.error message.join("\n")

        abnormal_execution_plans.each do |ep|
          ep.update_state case ep.state
                          when :planning
                            :stopped
                          when :running
                            :paused
                          else
                            raise
                          end
          ep.steps.values.each do |step|
            if [:suspended, :running].include?(step.state)
              step.error = ExecutionPlan::Steps::Error.new("Abnormal termination (previous state: #{step.state})")
              step.state = :error
              step.save
            end
          end
        end
      end
    end

    # should be called after World is initialized, SimpleWorld does it automatically
    def execute_planned_execution_plans
      planned_execution_plans =
          self.persistence.find_execution_plans filters: { 'state' => %w(planned) }
      planned_execution_plans.each { |ep| execute ep.id }
    end

    private

    def calculate_subscription_index
      @subscription_index =
          action_classes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |klass, index|
            next unless klass.subscribe
            Array(klass.subscribe).each do |subscribed_class|
              index[subscribed_class.to_s.constantize] << klass
            end
          end.tap { |o| o.freeze }
    end

  end
end
