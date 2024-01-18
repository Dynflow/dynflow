# -*- coding: utf-8 -*-
# frozen_string_literal: true
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
      @config = Config::ForWorld.new(config, self)

      # Set the telemetry instance as soon as possible
      Dynflow::Telemetry.set_adapter @config.telemetry_adapter
      Dynflow::Telemetry.register_metrics!

      @id                     = SecureRandom.uuid
      @logger_adapter         = @config.logger_adapter
      @clock                  = spawn_and_wait(Clock, 'clock', logger)
      @config.validate
      @transaction_adapter    = @config.transaction_adapter
      @persistence            = Persistence.new(self, @config.persistence_adapter,
                                                :backup_deleted_plans => @config.backup_deleted_plans,
                                                :backup_dir => @config.backup_dir)
      @coordinator            = Coordinator.new(@config.coordinator_adapter)
      if @config.executor
        @executor = Executors::Parallel.new(self,
                                            executor_class: @config.executor,
                                            heartbeat_interval: @config.executor_heartbeat_interval,
                                            queues_options: @config.queues)
      end
      @action_classes         = @config.action_classes
      @auto_rescue            = @config.auto_rescue
      @exit_on_terminate      = Concurrent::AtomicBoolean.new(@config.exit_on_terminate)
      @connector              = @config.connector
      @middleware             = Middleware::World.new
      @middleware.use Middleware::Common::Transaction if @transaction_adapter
      @client_dispatcher      = spawn_and_wait(Dispatcher::ClientDispatcher, "client-dispatcher", self, @config.ping_cache_age)
      @dead_letter_handler    = spawn_and_wait(DeadLetterSilencer, 'default_dead_letter_handler', @config.silent_dead_letter_matchers)
      @auto_validity_check    = @config.auto_validity_check
      @validity_check_timeout = @config.validity_check_timeout
      @throttle_limiter       = @config.throttle_limiter
      @terminated             = Concurrent::Promises.resolvable_event
      @termination_timeout    = @config.termination_timeout
      calculate_subscription_index

      if executor
        @executor_dispatcher = spawn_and_wait(Dispatcher::ExecutorDispatcher, "executor-dispatcher", self, @config.executor_semaphore)
        executor.initialized.wait
      end
      update_register
      perform_validity_checks if auto_validity_check

      @termination_barrier = Mutex.new
      @before_termination_hooks = Queue.new

      if @config.auto_terminate
        at_exit do
          @exit_on_terminate.make_false # make sure we don't terminate twice
          self.terminate.wait
        end
      end
      post_initialization
    end

    # performs steps once the executor is ready and invalidation of previous worls is finished.
    # Needs to be indempotent, as it can be called several times (expecially when auto_validity_check
    # if false, as it should be called after `perform_validity_checks` method)
    def post_initialization
      @delayed_executor ||= try_spawn(:delayed_executor, Coordinator::DelayedExecutorLock)
      @execution_plan_cleaner ||= try_spawn(:execution_plan_cleaner, Coordinator::ExecutionPlanCleanerLock)
      update_register
      @delayed_executor.start if auto_validity_check && @delayed_executor && !@delayed_executor.started?
      self.auto_execute if @config.auto_execute
    end

    def before_termination(&block)
      @before_termination_hooks << block
    end

    def update_register
      @meta                     ||= @config.meta
      @meta['queues']           = @config.queues if @executor
      @meta['delayed_executor'] = true if @delayed_executor
      @meta['execution_plan_cleaner'] = true if @execution_plan_cleaner
      @meta['last_seen'] = Dynflow::Dispatcher::ClientDispatcher::PingCache.format_time
      if @already_registered
        coordinator.update_record(registered_world)
      else
        coordinator.register_world(registered_world)
        @already_registered = true
      end
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
      Triggered       = type { fields! execution_plan_id: String, future: Concurrent::Promises::ResolvableFuture }

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
        done = execute(execution_plan.id, Concurrent::Promises.resolvable_future)
        Triggered[execution_plan.id, done]
      else
        PlaningFailed[execution_plan.id, execution_plan.errors.first.exception]
      end
    end

    def delay(action_class, delay_options, *args)
      delay_with_options(action_class: action_class, args: args, delay_options: delay_options)
    end

    def delay_with_options(action_class:, args:, delay_options:, id: nil, caller_action: nil)
      raise 'No action_class given' if action_class.nil?
      execution_plan = ExecutionPlan.new(self, id)
      execution_plan.delay(caller_action, action_class, delay_options, *args)
      Scheduled[execution_plan.id]
    end

    def plan_elsewhere(action_class, *args)
      execution_plan = ExecutionPlan.new(self, nil)
      execution_plan.delay(nil, action_class, {}, *args)
      plan_request(execution_plan.id)

      Scheduled[execution_plan.id]
    end

    def plan(action_class, *args)
      plan_with_options(action_class: action_class, args: args)
    end

    def plan_with_options(action_class:, args:, id: nil, caller_action: nil)
      ExecutionPlan.new(self, id).tap do |execution_plan|
        coordinator.acquire(Coordinator::PlanningLock.new(self, execution_plan.id)) do
          execution_plan.prepare(action_class, caller_action: caller_action)
          execution_plan.plan(*args)
        end
      end
    end

    # @return [Concurrent::Promises::ResolvableFuture] containing execution_plan when finished
    # raises when ExecutionPlan is not accepted for execution
    def execute(execution_plan_id, done = Concurrent::Promises.resolvable_future)
      publish_request(Dispatcher::Execution[execution_plan_id], done, true)
    end

    def event(execution_plan_id, step_id, event, done = Concurrent::Promises.resolvable_future, optional: false)
      publish_request(Dispatcher::Event[execution_plan_id, step_id, event, nil, optional], done, false)
    end

    def plan_event(execution_plan_id, step_id, event, time, accepted = Concurrent::Promises.resolvable_future, optional: false)
      publish_request(Dispatcher::Event[execution_plan_id, step_id, event, time, optional], accepted, false)
    end

    def plan_request(execution_plan_id, done = Concurrent::Promises.resolvable_future)
      publish_request(Dispatcher::Planning[execution_plan_id], done, false)
    end

    def ping(world_id, timeout, done = Concurrent::Promises.resolvable_future)
      publish_request(Dispatcher::Ping[world_id, true], done, false, timeout)
    end

    def ping_without_cache(world_id, timeout, done = Concurrent::Promises.resolvable_future)
      publish_request(Dispatcher::Ping[world_id, false], done, false, timeout)
    end

    def get_execution_status(world_id, execution_plan_id, timeout, done = Concurrent::Promises.resolvable_future)
      publish_request(Dispatcher::Status[world_id, execution_plan_id], done, false, timeout)
    end

    def publish_request(request, done, wait_for_accepted, timeout = nil)
      accepted = Concurrent::Promises.resolvable_future
      accepted.rescue do |reason|
        done.reject reason if reason
      end
      client_dispatcher.ask([:publish_request, done, request, timeout], accepted)
      accepted.wait if wait_for_accepted
      done
    rescue => e
      accepted.reject e
    end

    def terminate(future = Concurrent::Promises.resolvable_future)
      start_termination.tangle(future)
      future
    end

    def terminating?
      defined?(@terminating)
    end

    # 24119 - ensure delayed executor is preserved after invalidation
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
    rescue Coordinator::LockError
      nil
    end

    private

    def start_termination
      @termination_barrier.synchronize do
        return @terminating if @terminating
        termination_future ||= Concurrent::Promises.future do
          begin
            run_before_termination_hooks

            if delayed_executor
              logger.info "start terminating delayed_executor..."
              delayed_executor.terminate.wait(termination_timeout)
            end

            logger.info "start terminating throttle_limiter..."
            throttle_limiter.terminate.wait(termination_timeout)

            if executor
              connector.stop_receiving_new_work(self, termination_timeout)

              logger.info "start terminating executor..."
              executor.terminate.wait(termination_timeout)

              logger.info "start terminating executor dispatcher..."
              executor_dispatcher_terminated = Concurrent::Promises.resolvable_future
              executor_dispatcher.ask([:start_termination, executor_dispatcher_terminated])
              executor_dispatcher_terminated.wait(termination_timeout)
            end

            logger.info "start terminating client dispatcher..."
            client_dispatcher_terminated = Concurrent::Promises.resolvable_future
            client_dispatcher.ask([:start_termination, client_dispatcher_terminated])
            client_dispatcher_terminated.wait(termination_timeout)

            logger.info "stop listening for new events..."
            connector.stop_listening(self, termination_timeout)

            if @clock
              logger.info "start terminating clock..."
              clock.ask(:terminate!).wait(termination_timeout)
            end

            coordinator.delete_world(registered_world)
            @terminated.resolve
            true
          rescue => e
            logger.fatal(e)
          end
        end
        @terminating = Concurrent::Promises.future do
          termination_future.wait(termination_timeout)
        end.on_resolution do
          @terminated.resolve
          Thread.new { Kernel.exit } if @exit_on_terminate.true?
        end
      end
    end

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
        hook_run = Concurrent::Promises.future do
          begin
            @before_termination_hooks.pop.call
          rescue => e
            logger.error e
          end
        end
        logger.error "timeout running before_termination_hook" unless hook_run.wait(termination_timeout)
      end
    end

    def spawn_and_wait(klass, name, *args)
      initialized = Concurrent::Promises.resolvable_future
      actor = klass.spawn(name: name, args: args, initialized: initialized)
      initialized.wait
      return actor
    end

  end
end
