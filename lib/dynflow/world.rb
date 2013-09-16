module Dynflow
  class World
    include Algebrick::TypeCheck

    attr_reader :executor, :persistence, :transaction_adapter, :action_classes, :subscription_index

    def initialize(options = {})
      options = self.default_options.merge(options)

      @executor            = options[:executor] || Executors::Parallel.new(self, options[:pool_size])
      is_kind_of! @executor, Executors::Abstract

      persistence_adapter  = is_kind_of! options[:persistence_adapter], PersistenceAdapters::Abstract
      @persistence         = Persistence.new(self, persistence_adapter)
      @transaction_adapter = is_kind_of! options[:transaction_adapter], TransactionAdapters::Abstract
      @suspended_actions   = {}

      @action_classes     = options[:action_classes]
      @subscription_index = action_classes.inject(Hash.new { |h, k| h[k] = [] }) do |index, klass|
        next index unless klass.subscribe
        index[klass.subscribe] << klass
        index
      end.tap { |o| o.freeze }
    end

    def default_options
      { action_classes: Action.all_children }
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

    def execute(execution_plan_id)
      executor.execute execution_plan_id
    end

    # FIND add a future to signal results?
    def update_progress(suspended_action, done, *args)
      executor.update_progress suspended_action, done, *args
    end
  end
end
