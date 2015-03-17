# -*- coding: utf-8 -*-
module Dynflow
  class World
    include Algebrick::TypeCheck
    include Algebrick::Matching

    attr_reader :id, :client_dispatcher, :executor_dispatcher, :executor, :connector,
        :transaction_adapter, :logger_adapter, :coordinator,
        :persistence, :action_classes, :subscription_index,
        :middleware, :auto_rescue, :clock

    def initialize(config)
      @id                   = SecureRandom.uuid
      @clock                = Clock.spawn('clock')
      config_for_world      = Config::ForWorld.new(config, self)
      config_for_world.validate
      @logger_adapter       = config_for_world.logger_adapter
      @transaction_adapter  = config_for_world.transaction_adapter
      @persistence          = Persistence.new(self, config_for_world.persistence_adapter)
      @coordinator          = Coordinator.new(config_for_world.coordinator_adapter)
      @executor             = config_for_world.executor
      @action_classes       = config_for_world.action_classes
      @auto_rescue          = config_for_world.auto_rescue
      @exit_on_terminate    = config_for_world.exit_on_terminate
      @connector            = config_for_world.connector
      @middleware           = Middleware::World.new
      @client_dispatcher    = Dispatcher::ClientDispatcher.spawn("client-dispatcher", self)
      calculate_subscription_index

      if executor
        @executor_dispatcher = Dispatcher::ExecutorDispatcher.spawn("executor-dispatcher", self)
        executor.initialized.wait
      end
      coordinator.register_world(registered_world)
      @termination_barrier = Mutex.new

      at_exit { self.terminate.wait } if config_for_world.auto_terminate
      self.consistency_check if config_for_world.consistency_check
      self.auto_execute if config_for_world.auto_execute
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
          klass.to_s.constantize
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
      Triggered       = type { fields! execution_plan_id: String, future: Concurrent::IVar }

      variants PlaningFailed, Triggered
    end

    module TriggerResult
      def planned?
        match self, PlaningFailed => false, Triggered => true
      end

      def triggered?
        match self, PlaningFailed => false, Triggered => true
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
        done = execute(execution_plan.id, Concurrent::IVar.new)
        Triggered[execution_plan.id, done]
      else
        PlaningFailed[execution_plan.id, execution_plan.errors.first.exception]
      end
    end

    def plan(action_class, *args)
      ExecutionPlan.new(self).tap do |execution_plan|
        execution_plan.prepare(action_class)
        execution_plan.plan(*args)
      end
    end

    # @return [Concurrent::IVar] containing execution_plan when finished
    # raises when ExecutionPlan is not accepted for execution
    def execute(execution_plan_id, done = Concurrent::IVar.new)
      publish_request(Dispatcher::Execution[execution_plan_id], done, true)
    end

    def event(execution_plan_id, step_id, event, done = Concurrent::IVar.new)
      publish_request(Dispatcher::Event[execution_plan_id, step_id, event], done, false)
    end

    def ping(world_id, timeout, done = Concurrent::IVar.new)
      publish_request(Dispatcher::Ping[world_id], done, false, timeout)
    end

    def publish_request(request, done, wait_for_accepted, timeout = nil)
      accepted = Concurrent::IVar.new.with_observer do |_, value, reason|
        done.fail reason if reason
      end
      client_dispatcher.ask([:publish_request, done, request, timeout], accepted)
      accepted.wait if wait_for_accepted
      done
    rescue => e
      accepted.fail e
    end

    def receive(envelope)
      Type! envelope, Dispatcher::Envelope
      match(envelope.message,
            (on Dispatcher::Ping do
               response_envelope = envelope.build_response_envelope(Dispatcher::Pong, self)
               connector.send(response_envelope)
             end),
            (on Dispatcher::Request do
               executor_dispatcher.tell([:handle_request, envelope])
             end),
            (on Dispatcher::Response do
               client_dispatcher.tell([:dispatch_response, envelope])
             end))
    end

    def terminate(future = Concurrent::IVar.new)
      @termination_barrier.synchronize do
        @terminated ||= Concurrent::Promise.execute do
          begin
            # TODO: refactory once we can chain futures (probably after migrating
            #       to concurrent-ruby promises

            coordinator.deactivate_world(registered_world) if executor
            logger.info "stop listening for new events..."
            listening_stopped     = connector.stop_listening(self)
            listening_stopped.wait

            if executor
              logger.info "start terminating executor..."
              executor.terminate.wait

              logger.info "start terminating executor dispatcher..."
              executor_dispatcher.ask(:terminate!).wait
            end


            logger.info "start terminating client dispatcher..."
            client_dispatcher_terminated = Concurrent::IVar.new
            client_dispatcher.ask([:start_termination, client_dispatcher_terminated])
            client_dispatcher_terminated.wait

            if @clock
              logger.info "start terminating clock..."
              clock.ask(:terminate!).wait
            end

            connector.terminate

            coordinator.release_by_owner("world:#{registered_world.id}")
            coordinator.delete_world(registered_world)
            if @exit_on_terminate
              Kernel.exit
            end
          rescue => e
            logger.fatal(e)
          end
        end
      end

      @terminated.then { future.set true }
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
        old_execution_locks = coordinator.find_locks(class: Coordinator::ExecutionLock.name,
                                                     owner_id: "world:#{world.id}")

        coordinator.deactivate_world(world)

        old_execution_locks.each do |execution_lock|
          invalidate_execution_lock(execution_lock)
        end

        coordinator.delete_world(world)
      end
    end

    def invalidate_execution_lock(execution_lock)
      plan = persistence.load_execution_plan(execution_lock.execution_plan_id)
      plan.execution_history.add('terminate execution', execution_lock.world_id)

      plan.steps.values.each do |step|
        if step.state == :running
          step.error = ExecutionPlan::Steps::Error.new("Abnormal termination (previous state: #{step.state})")
          step.state = :error
          step.save
        end
      end

      plan.update_state(:paused) unless plan.state == :paused
      plan.save
      coordinator.release(execution_lock)
      unless plan.error?
        client_dispatcher.tell([:dispatch_request,
                                Dispatcher::Execution[execution_lock.execution_plan_id],
                                execution_lock.client_world_id,
                                execution_lock.request_id])
      end
    rescue Errors::PersistenceError
      logger.error "failed to write data while invalidating execution lock #{execution_lock}"
    end

    # executes plans that are planned/paused and haven't reported any error yet (usually when no executor
    # was available by the time of planning or terminating)
    def auto_execute
      coordinator.acquire(Coordinator::AutoExecuteLock.new(self)) do
        planned_execution_plans =
            self.persistence.find_execution_plans filters: { 'state' => %w(planned paused), 'result' => 'pending' }
        planned_execution_plans.each { |ep| execute ep.id }
      end
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
