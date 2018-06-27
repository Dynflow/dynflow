# -*- coding: utf-8 -*-
require 'dynflow/world/invalidation'

module Dynflow
  class World
    include Algebrick::TypeCheck
    include Algebrick::Matching
    include Invalidation

    attr_reader :id, :config, :client_dispatcher, :executor_dispatcher, :executor, :connector,
                :transaction_adapter, :logger_adapter, :coordinator,
                :persistence, :action_classes, :subscription_index,
                :middleware, :auto_rescue, :clock, :meta, :delayed_executor, :auto_validity_check, :validity_check_timeout, :throttle_limiter,
                :termination_timeout, :terminated, :dead_letter_handler, :execution_plan_cleaner

    def initialize(config)
      @id                     = SecureRandom.uuid
      @clock                  = spawn_and_wait(Clock, 'clock')
      @config                 = Config::ForWorld.new(config, self)
      @logger_adapter         = @config.logger_adapter
      @config.validate
      @transaction_adapter    = @config.transaction_adapter
      @persistence            = Persistence.new(self, @config.persistence_adapter,
                                                :backup_deleted_plans => @config.backup_deleted_plans,
                                                :backup_dir => @config.backup_dir)
      @coordinator            = Coordinator.new(@config.coordinator_adapter)
      @executor               = @config.executor
      @action_classes         = @config.action_classes
      @auto_rescue            = @config.auto_rescue
      @exit_on_terminate      = Concurrent::AtomicBoolean.new(@config.exit_on_terminate)
      @connector              = @config.connector
      @middleware             = Middleware::World.new
      @middleware.use Middleware::Common::Transaction if @transaction_adapter
      @client_dispatcher      = spawn_and_wait(Dispatcher::ClientDispatcher, "client-dispatcher", self)
      @dead_letter_handler    = spawn_and_wait(DeadLetterSilencer, 'default_dead_letter_handler', @config.silent_dead_letter_matchers)
      @auto_validity_check    = @config.auto_validity_check
      @validity_check_timeout = @config.validity_check_timeout
      @throttle_limiter       = @config.throttle_limiter
      @terminated             = Concurrent.event
      @termination_timeout    = @config.termination_timeout
      calculate_subscription_index

      if executor
        @executor_dispatcher = spawn_and_wait(Dispatcher::ExecutorDispatcher, "executor-dispatcher", self, @config.executor_semaphore)
        executor.initialized.wait
      end
      perform_validity_checks if auto_validity_check

      @delayed_executor         = try_spawn(:delayed_executor, Coordinator::DelayedExecutorLock)
      @execution_plan_cleaner   = try_spawn(:execution_plan_cleaner, Coordinator::ExecutionPlanCleanerLock)
      @meta                     = @config.meta
      @meta['queues']           = @config.queues if @executor
      @meta['delayed_executor'] = true if @delayed_executor
      @meta['execution_plan_cleaner'] = true if @execution_plan_cleaner
      coordinator.register_world(registered_world)
      @termination_barrier = Mutex.new
      @before_termination_hooks = Queue.new

      if @config.auto_terminate
        at_exit do
          @exit_on_terminate.make_false # make sure we don't terminate twice
          self.terminate.wait
        end
      end
      self.auto_execute if @config.auto_execute
      @delayed_executor.start if @delayed_executor
    end

    def before_termination(&block)
      @before_termination_hooks << block
    end

    def registered_world
      if executor
        Coordinator::ExecutorWorld.new(self)
      else
        Coordinator::ClientWorld.new(self)
      end
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
      # TODO what happens with newly loaded classes
      @action_classes = @action_classes.map do |klass|
        begin
          Utils.constantize(klass.to_s)
        rescue NameError
          nil # ignore missing classes
        end
      end.compact
      middleware.clear_cache!
      calculate_subscription_index
    end

    TriggerResult = Algebrick.type do
      # Returned by #trigger when planning fails.
      PlaningFailed   = type { fields! execution_plan_id: String, error: Exception }
      # Returned by #trigger when planning is successful, #future will resolve after
      # ExecutionPlan is executed.
      Triggered       = type { fields! execution_plan_id: String, future: Concurrent::Edge::Future }

      Scheduled       = type { fields! execution_plan_id: String }

      variants PlaningFailed, Triggered, Scheduled
    end

    module TriggerResult
      def planned?
        match self, PlaningFailed => false, Triggered => true, Scheduled => false
      end

      def triggered?
        match self, PlaningFailed => false, Triggered => true, Scheduled => false
      end

      def scheduled?
        match self, PlaningFailed => false, Triggered => false, Scheduled => true
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
    # if no arguments given, the plan is expected to be returned by a block
    def trigger(action_class = nil, *args, &block)
      if action_class.nil?
        raise 'Neither action_class nor a block given' if block.nil?
        execution_plan = block.call(self)
      else
        execution_plan = plan(action_class, *args)
      end
      planned = execution_plan.state == :planned

      if planned
        done = execute(execution_plan.id, Concurrent.future)
        Triggered[execution_plan.id, done]
      else
        PlaningFailed[execution_plan.id, execution_plan.errors.first.exception]
      end
    end

    def delay(*args)
      delay_with_caller(nil, *args)
    end

    def delay_with_caller(caller_action, action_class, delay_options, *args)
      raise 'No action_class given' if action_class.nil?
      execution_plan = ExecutionPlan.new(self)
      execution_plan.delay(caller_action, action_class, delay_options, *args)
      Scheduled[execution_plan.id]
    end

    def plan(action_class, *args)
      ExecutionPlan.new(self).tap do |execution_plan|
        execution_plan.prepare(action_class)
        execution_plan.plan(*args)
      end
    end

    def plan_with_caller(caller_action, action_class, *args)
      ExecutionPlan.new(self).tap do |execution_plan|
        execution_plan.prepare(action_class, caller_action: caller_action)
        execution_plan.plan(*args)
      end
    end

    # @return [Concurrent::Edge::Future] containing execution_plan when finished
    # raises when ExecutionPlan is not accepted for execution
    def execute(execution_plan_id, done = Concurrent.future)
      publish_request(Dispatcher::Execution[execution_plan_id], done, true)
    end

    def event(execution_plan_id, step_id, event, done = Concurrent.future)
      publish_request(Dispatcher::Event[execution_plan_id, step_id, event], done, false)
    end

    def ping(world_id, timeout, done = Concurrent.future)
      publish_request(Dispatcher::Ping[world_id], done, false, timeout)
    end

    def get_execution_status(world_id, execution_plan_id, timeout, done = Concurrent.future)
      publish_request(Dispatcher::Status[world_id, execution_plan_id], done, false, timeout)
    end

    def publish_request(request, done, wait_for_accepted, timeout = nil)
      accepted = Concurrent.future
      accepted.rescue do |reason|
        done.fail reason if reason
      end
      client_dispatcher.ask([:publish_request, done, request, timeout], accepted)
      accepted.wait if wait_for_accepted
      done
    rescue => e
      accepted.fail e
    end

    def terminate(future = Concurrent.future)
      @termination_barrier.synchronize do
        @terminating ||= Concurrent.future do
          begin
            run_before_termination_hooks

            if delayed_executor
              logger.info "start terminating delayed_executor..."
              delayed_executor.terminate.wait(termination_timeout)
            end

            logger.info "start terminating throttle_limiter..."
            throttle_limiter.terminate.wait(termination_timeout)

            if executor
              connector.stop_receiving_new_work(self)

              logger.info "start terminating executor..."
              executor.terminate.wait(termination_timeout)

              logger.info "start terminating executor dispatcher..."
              executor_dispatcher_terminated = Concurrent.future
              executor_dispatcher.ask([:start_termination, executor_dispatcher_terminated])
              executor_dispatcher_terminated.wait(termination_timeout)
            end

            logger.info "start terminating client dispatcher..."
            client_dispatcher_terminated = Concurrent.future
            client_dispatcher.ask([:start_termination, client_dispatcher_terminated])
            client_dispatcher_terminated.wait(termination_timeout)

            logger.info "stop listening for new events..."
            connector.stop_listening(self)

            if @clock
              logger.info "start terminating clock..."
              clock.ask(:terminate!).wait(termination_timeout)
            end

            coordinator.delete_world(registered_world)
            @terminated.complete
            true
          rescue => e
            logger.fatal(e)
          end
        end.on_completion do
          Thread.new { Kernel.exit } if @exit_on_terminate.true?
        end
      end

      @terminating.tangle(future)
      future
    end

    def terminating?
      defined?(@terminating)
    end

    # executes plans that are planned/paused and haven't reported any error yet (usually when no executor
    # was available by the time of planning or terminating)
    def auto_execute
      coordinator.acquire(Coordinator::AutoExecuteLock.new(self)) do
        planned_execution_plans =
            self.persistence.find_execution_plans filters: { 'state' => %w(planned paused), 'result' => (ExecutionPlan.results - [:error]).map(&:to_s) }
        planned_execution_plans.map do |ep|
          if coordinator.find_locks(Dynflow::Coordinator::ExecutionLock.unique_filter(ep.id)).empty?
            execute(ep.id)
          end
        end.compact
      end
    rescue Coordinator::LockError => e
      logger.info "auto-executor lock already aquired: #{e.message}"
      []
    end

    def try_spawn(what, lock_class = nil)
      object = nil
      return nil if !executor || (object = @config.public_send(what)).nil?

      coordinator.acquire(lock_class.new(self)) if lock_class
      object.spawn.wait
      object
    rescue Coordinator::LockError => e
      nil
    end

    private
    def calculate_subscription_index
      @subscription_index =
          action_classes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |klass, index|
            next unless klass.subscribe
            Array(klass.subscribe).each do |subscribed_class|
              index[Utils.constantize(subscribed_class.to_s)] << klass
            end
          end.tap { |o| o.freeze }
    end

    def run_before_termination_hooks
      until @before_termination_hooks.empty?
        begin
          @before_termination_hooks.pop.call
        rescue => e
          logger.error e
        end
      end
    end

    def spawn_and_wait(klass, name, *args)
      initialized = Concurrent.future
      actor = klass.spawn(name: name, args: args, initialized: initialized)
      initialized.wait
      return actor
    end

  end
end
