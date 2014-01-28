module Dynflow
  class World
    include Algebrick::TypeCheck

    attr_reader :executor, :persistence, :transaction_adapter, :action_classes, :subscription_index,
                :logger_adapter, :options

    def initialize(options_hash = {})
      @options             = default_options.merge options_hash
      @logger_adapter      = Type! option_val(:logger_adapter), LoggerAdapters::Abstract
      @transaction_adapter = Type! option_val(:transaction_adapter), TransactionAdapters::Abstract
      persistence_adapter  = Type! option_val(:persistence_adapter), PersistenceAdapters::Abstract
      @persistence         = Persistence.new(self, persistence_adapter)
      @executor            = Type! option_val(:executor), Executors::Abstract
      @action_classes      = option_val(:action_classes)
      calculate_subscription_index

      executor.initialized.wait
      @termination_barrier = Mutex.new

      transaction_adapter.check self
    end

    def default_options
      @default_options ||=
          { action_classes: Action.all_children,
            logger_adapter: LoggerAdapters::Simple.new,
            executor:       -> world { Executors::Parallel.new(world, options[:pool_size]) } }
    end

    def clock
      @clock ||= Clock.new(logger)
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
      calculate_subscription_index
    end

    class TriggerResult
      include Algebrick::TypeCheck

      attr_reader :execution_plan_id, :planned, :finished
      alias_method :id, :execution_plan_id
      alias_method :planned?, :planned

      def initialize(execution_plan_id, planned, finished)
        @execution_plan_id = Type! execution_plan_id, String
        @planned           = Type! planned, TrueClass, FalseClass
        @finished          = Type! finished, Future
      end

      def to_a
        [execution_plan_id, planned, finished]
      end
    end

    # @return [TriggerResult]
    # blocks until action_class is planned
    def trigger(action_class, *args)
      execution_plan = plan(action_class, *args)
      planned        = execution_plan.state == :planned
      finished       = if planned
                         begin
                           execute(execution_plan.id) # TODO fix the api not to raise
                         rescue => exception
                           Future.new.fail exception
                         end
                       else
                         Future.new.resolve(execution_plan)
                       end
      return TriggerResult.new(execution_plan.id, planned, finished)
    end

    def event(execution_plan_id, step_id, event, future = Future.new)
      executor.event execution_plan_id, step_id, event, future
    end

    def plan(action_class, *args)
      ExecutionPlan.new(self).tap do |execution_plan|
        execution_plan.prepare(action_class)
        execution_plan.plan(*args)
      end
    end

    # @return [Future] containing execution_plan when finished
    # raises when ExecutionPlan is not accepted for execution
    def execute(execution_plan_id, finished = Future.new)
      executor.execute execution_plan_id, finished
    end

    def terminate(future = Future.new)
      @termination_barrier.synchronize do
        if @executor_terminated.nil?
          @executor_terminated = Future.new
          @clock_terminated    = Future.new
          executor.terminate(@executor_terminated).
              do_then { clock.ask(MicroActor::Terminate, @clock_terminated) }
        end
      end
      Future.join([@executor_terminated, @clock_terminated], future)
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
          self.persistence.find_execution_plans filters: { 'state' => %w(running planning) }
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
        end
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
