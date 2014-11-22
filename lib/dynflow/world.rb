module Dynflow
  class World
    include Algebrick::TypeCheck

    attr_reader :executor, :persistence, :transaction_adapter, :action_classes, :subscription_index,
                :logger_adapter, :options, :middleware, :auto_rescue

    def initialize(options_hash = {})
      @options             = default_options.merge options_hash
      @logger_adapter      = Type! option_val(:logger_adapter), LoggerAdapters::Abstract
      @transaction_adapter = Type! option_val(:transaction_adapter), TransactionAdapters::Abstract
      persistence_adapter  = Type! option_val(:persistence_adapter), PersistenceAdapters::Abstract
      @persistence         = Persistence.new(self, persistence_adapter)
      @executor            = Type! option_val(:executor), Executors::Abstract
      @action_classes      = option_val(:action_classes)
      @auto_rescue         = option_val(:auto_rescue)
      @middleware          = Middleware::World.new
      calculate_subscription_index

      executor.initialized.wait
      @termination_barrier = Mutex.new

      transaction_adapter.check self
    end

    def default_options
      @default_options ||=
          { action_classes: Action.all_children,
            logger_adapter: LoggerAdapters::Simple.new,
            executor:       -> world { Executors::Parallel.new(world, options[:pool_size]) },
            auto_rescue:    true }
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
          Triggered[execution_plan.id, execute(execution_plan.id)]
        rescue => exception
          ExecutionFailed[execution_plan.id, exception]
        end
      else
        PlaningFailed[execution_plan.id, execution_plan.errors.first.exception]
      end
    end

    def event(execution_plan_id, step_id, event, future = Concurrent::IVar.new)
      executor.event execution_plan_id, step_id, event, future
    end

    def plan(action_class, *args)
      ExecutionPlan.new(self).tap do |execution_plan|
        execution_plan.prepare(action_class)
        execution_plan.plan(*args)
      end
    end

    # @return [Concurrent::IVar] containing execution_plan when finished
    # raises when ExecutionPlan is not accepted for execution
    def execute(execution_plan_id, finished = Concurrent::IVar.new)
      executor.execute execution_plan_id, finished
    end

    def terminate(future = Concurrent::IVar.new)
      @termination_barrier.synchronize do
        if @executor_terminated.nil?
          @executor_terminated = Concurrent::IVar.new
          @clock_terminated    = Concurrent::IVar.new
          executor.terminate(@executor_terminated).
              with_observer { clock.ask(:terminate!, @clock_terminated) }
        end
      end

      # TODO fix me do not block, replace with IVar.join/zip when available
      @executor_terminated.wait
      @clock_terminated.wait
      future.set true
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

    def option_val(key)
      val = options.fetch(key)
      if val.is_a? Proc
        options[key] = val.call(self)
      else
        val
      end
    end
  end
end
