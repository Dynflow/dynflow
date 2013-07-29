module Dynflow
  class World
    include Algebrick::TypeCheck

    attr_reader :executor, :persistence_adapter, :transaction_adapter, :action_classes, :subscription_index

    def initialize(executor, persistence_adapter, transaction_adapter, action_classes = Action.all_children)
      @executor            = is_kind_of! executor, Executors::Abstract
      @persistence_adapter = is_kind_of! persistence_adapter, PersistenceAdapters::Abstract
      @transaction_adapter = is_kind_of! transaction_adapter, TransactionAdapters::Abstract
      @suspended_actions   = {}

      @action_classes     = action_classes
      @subscription_index = action_classes.inject(Hash.new { |h, k| h[k] = [] }) do |index, klass|
        next index unless klass.subscribe
        index[klass.subscribe] << klass
        index
      end.tap { |o| o.freeze }
    end

    def subscribed_actions(action_class)
      @subscription_index.has_key?(action_class) ? @subscription_index[action_class] : []
    end

    # @return [Future]
    def trigger(action_class, *args)
      execution_plan = plan(action_class, *args)

      return execution_plan.id, unless execution_plan.success?
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

    ## world.wakeup(step_id, :finished, task)
    ## world.wakeup(step_id, :update_progress, tasks['progress'])
    #def wake_up(step_id, method, *args)
    #  @suspended_actions[step_id] # TODO tell executor to weak up the action with method(*args)
    #end
  end
end
