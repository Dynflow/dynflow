module Dynflow
  class World
    include Algebrick::TypeCheck

    attr_reader :executor, :persistence, :transaction_adapter, :action_classes, :subscription_index,
                :logger_adapter, :options, :initialized

    def initialize(options_hash = {}, &options_block)
      @initialized    = Future.new
      @logger_adapter = Type! options_hash.delete(:logger_adapter) || default_options[:logger_adapter],
                              LoggerAdapters::Abstract
      user_options    = options_hash.merge(if options_block
                                             Type!(options_block.call(self), Hash)
                                           else
                                             {}
                                           end)
      raise ArgumentError, ':logger_adapter option can be specified only in options_hash' if user_options.key? :logger_adapter
      options = self.default_options.merge(user_options)

      initialize_executor(options)
      initialize_persistence(options)
      initialize_transaction_adapter(options)

      @action_classes = options.delete(:action_classes)
      calculate_subscription_index

      @options = options
      @initialized.resolve true
    end

    def default_options
      @default_options ||= { action_classes: Action.all_children,
                             logger_adapter: LoggerAdapters::Simple.new }
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
    def trigger(action_class, *args)
      execution_plan = plan(action_class, *args)
      planned        = execution_plan.state == :planned
      finished       = if planned
                         execute(execution_plan.id)
                       else
                         Future.new.resolve(execution_plan)
                       end
      return TriggerResult.new(execution_plan.id, planned, finished)
    end

    def plan(action_class, *args)
      ExecutionPlan.new(self).tap do |execution_plan|
        execution_plan.prepare(action_class)
        execution_plan.plan(*args)
      end
    end

    # @return [Future] containing execution_plan when finished
    def execute(execution_plan_id, finished = Future.new)
      executor.execute execution_plan_id, finished
    end

    def terminate!(future = Future.new)
      executor.terminate! future
    end

    protected

    def initialize_executor(options)
      @executor =
          Type! options.delete(:executor) || Executors::Parallel.new(self, options[:pool_size]),
                Executors::Abstract
    end

    def initialize_persistence(options)
      persistence_adapter = Type! options.delete(:persistence_adapter), PersistenceAdapters::Abstract
      @persistence        = Persistence.new(self, persistence_adapter)
    end

    def initialize_transaction_adapter(options)
      @transaction_adapter = Type! options.delete(:transaction_adapter), TransactionAdapters::Abstract
    end

    private

    def calculate_subscription_index
      @subscription_index = action_classes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |klass, index|
        next unless klass.subscribe
        Array(klass.subscribe).each { |subscribed_class| index[subscribed_class] << klass }
      end.tap { |o| o.freeze }
    end
  end
end
