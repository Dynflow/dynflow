# -*- coding: utf-8 -*-
module Dynflow
  class World
    include Algebrick::TypeCheck
    include Algebrick::Matching

    attr_reader :id, :client_dispatcher, :executor_dispatcher, :executor, :connector,
                :transaction_adapter, :logger_adapter, :coordinator,
                :persistence, :action_classes, :subscription_index,
                :middleware, :auto_rescue, :clock, :meta, :delayed_executor, :auto_validity_check, :validity_check_timeout, :throttle_limiter

    def initialize(config)
      @id                     = SecureRandom.uuid
      @clock                  = spawn_and_wait(Clock, 'clock')
      config_for_world        = Config::ForWorld.new(config, self)
      @logger_adapter         = config_for_world.logger_adapter
      config_for_world.validate
      @transaction_adapter    = config_for_world.transaction_adapter
      @persistence            = Persistence.new(self, config_for_world.persistence_adapter)
      @coordinator            = Coordinator.new(config_for_world.coordinator_adapter)
      @executor               = config_for_world.executor
      @action_classes         = config_for_world.action_classes
      @auto_rescue            = config_for_world.auto_rescue
      @exit_on_terminate      = Concurrent::AtomicBoolean.new(config_for_world.exit_on_terminate)
      @connector              = config_for_world.connector
      @middleware             = Middleware::World.new
      @middleware.use Middleware::Common::Transaction if @transaction_adapter
      @client_dispatcher      = spawn_and_wait(Dispatcher::ClientDispatcher, "client-dispatcher", self)
      @meta                   = config_for_world.meta
      @auto_validity_check    = config_for_world.auto_validity_check
      @validity_check_timeout = config_for_world.validity_check_timeout
      @throttle_limiter       = config_for_world.throttle_limiter
      calculate_subscription_index

      if executor
        @executor_dispatcher = spawn_and_wait(Dispatcher::ExecutorDispatcher, "executor-dispatcher", self, config_for_world.executor_semaphore)
        executor.initialized.wait
      end
      if auto_validity_check
        self.worlds_validity_check
        self.locks_validity_check
      end
      @delayed_executor         = try_spawn_delayed_executor(config_for_world)
      @meta                     = config_for_world.meta
      @meta['delayed_executor'] = true if @delayed_executor
      coordinator.register_world(registered_world)
      @termination_barrier = Mutex.new
      @before_termination_hooks = Queue.new

      if config_for_world.auto_terminate
        at_exit do
          @exit_on_terminate.make_false # make sure we don't terminate twice
          self.terminate.wait
        end
      end
      self.auto_execute if config_for_world.auto_execute
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
        @terminated ||= Concurrent.future do
          begin
            run_before_termination_hooks

            if delayed_executor
              logger.info "start terminating delayed_executor..."
              delayed_executor.terminate.wait
            end

            logger.info "start terminating throttle_limiter..."
            throttle_limiter.terminate.wait

            if executor
              connector.stop_receiving_new_work(self)

              logger.info "start terminating executor..."
              executor.terminate.wait

              logger.info "start terminating executor dispatcher..."
              executor_dispatcher_terminated = Concurrent.future
              executor_dispatcher.ask([:start_termination, executor_dispatcher_terminated])
              executor_dispatcher_terminated.wait
            end

            logger.info "start terminating client dispatcher..."
            client_dispatcher_terminated = Concurrent.future
            client_dispatcher.ask([:start_termination, client_dispatcher_terminated])
            client_dispatcher_terminated.wait

            logger.info "stop listening for new events..."
            connector.stop_listening(self)

            if @clock
              logger.info "start terminating clock..."
              clock.ask(:terminate!).wait
            end

            coordinator.delete_world(registered_world)
            true
          rescue => e
            logger.fatal(e)
          end
        end.on_completion do
          Thread.new { Kernel.exit } if @exit_on_terminate.true?
        end
      end

      @terminated.tangle(future)
      future
    end

    def terminating?
      defined?(@terminated)
    end

    # Invalidate another world, that left some data in the runtime,
    # but it's not really running
    def invalidate(world)
      Type! world, Coordinator::ClientWorld, Coordinator::ExecutorWorld
      coordinator.acquire(Coordinator::WorldInvalidationLock.new(self, world)) do
        if world.is_a? Coordinator::ExecutorWorld
          old_execution_locks = coordinator.find_locks(class: Coordinator::ExecutionLock.name,
                                                       owner_id: "world:#{world.id}")

          coordinator.deactivate_world(world)

          old_execution_locks.each do |execution_lock|
            invalidate_execution_lock(execution_lock)
          end
        end

        coordinator.delete_world(world)
      end
    end

    def invalidate_execution_lock(execution_lock)
      begin
        plan = persistence.load_execution_plan(execution_lock.execution_plan_id)
      rescue KeyError => e
        logger.error "invalidated execution plan #{execution_lock.execution_plan_id} missing, skipping"
        coordinator.release(execution_lock)
        return
      end
      plan.execution_history.add('terminate execution', execution_lock.world_id)

      plan.steps.values.each do |step|
        if step.state == :running
          step.error = ExecutionPlan::Steps::Error.new("Abnormal termination (previous state: #{step.state})")
          step.state = :error
          step.save
        end
      end

      plan.update_state(:paused) if plan.state == :running
      plan.save
      coordinator.release(execution_lock)

      available_executors = coordinator.find_worlds(true)
      if available_executors.any? && !plan.error?
        client_dispatcher.tell([:dispatch_request,
                                Dispatcher::Execution[execution_lock.execution_plan_id],
                                execution_lock.client_world_id,
                                execution_lock.request_id])
      end
    rescue Errors::PersistenceError
      logger.error "failed to write data while invalidating execution lock #{execution_lock}"
    end

    def worlds_validity_check(auto_invalidate = true, worlds_filter = {})
      worlds = coordinator.find_worlds(false, worlds_filter)

      world_checks = worlds.reduce({}) do |hash, world|
        hash.update(world => ping(world.id, self.validity_check_timeout))
      end
      world_checks.values.each(&:wait)

      results = {}
      world_checks.each do |world, check|
        if check.success?
          result = :valid
        else
          if auto_invalidate
            begin
              invalidate(world)
              result = :invalidated
            rescue => e
              logger.error e
              result = e.message
            end
          else
            result = :invalid
          end
        end
        results[world.id] = result
      end

      unless results.values.all? { |result| result == :valid }
        logger.error "invalid worlds found #{results.inspect}"
      end

      return results
    end

    def locks_validity_check
      orphaned_locks = coordinator.clean_orphaned_locks

      unless orphaned_locks.empty?
        logger.error "invalid coordinator locks found and invalidated: #{orphaned_locks.inspect}"
      end

      return orphaned_locks
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

    def try_spawn_delayed_executor(config_for_world)
      return nil if !executor || config_for_world.delayed_executor.nil?
      coordinator.acquire(Coordinator::DelayedExecutorLock.new(self))
      config_for_world.delayed_executor
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
