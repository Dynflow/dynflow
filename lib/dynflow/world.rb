module Dynflow
  class World
    include Algebrick::TypeCheck

    attr_reader :executor, :persistence, :transaction_adapter, :action_classes, :subscription_index,
                :logger_adapter, :options

    def initialize(options = {})
      @logger_adapter = is_kind_of!(options.delete(:logger_adapter) || LoggerAdapters::Simple.new,
                                    LoggerAdapters::Abstract)
      options         = self.default_options.merge(options)

      @executor = options.delete(:executor) || Executors::Parallel.new(self, options[:pool_size])
      is_kind_of! @executor, Executors::Abstract

      persistence_adapter  = is_kind_of! options.delete(:persistence_adapter), PersistenceAdapters::Abstract
      @persistence         = Persistence.new(self, persistence_adapter)
      @transaction_adapter = is_kind_of! options.delete(:transaction_adapter), TransactionAdapters::Abstract
      @action_classes      = options.delete(:action_classes)

      @suspended_actions  = {}
      @subscription_index = action_classes.inject(Hash.new { |h, k| h[k] = [] }) do |index, klass|
        next index unless klass.subscribe
        Array(klass.subscribe).each do |subscribed_class|
          index[subscribed_class] << klass
        end
        index
      end.tap { |o| o.freeze }

      @options = options
    end

    def default_options
      { action_classes: Action.all_children, step_warning_time_limit: 1 }
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

    # @return [Future]
    def trigger(action_class, *args)
      execution_plan = plan(action_class, *args)

      return execution_plan.id, if execution_plan.error?
                                  Future.new.set(execution_plan)
                                else
                                  execute execution_plan.id
                                end
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

    # FIND add a future to signal results?
    def update_progress(suspended_action, done, *args)
      executor.update_progress suspended_action, done, *args
    end

    def terminate!(future = Future.new)
      executor.terminate! future
    end
  end
end
