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
      execution_plan = ExecutionPlan.new(self, action_class)
      execution_plan.plan(*args)

      return execution_plan.id, unless execution_plan.success?
                                  Future.new.set(execution_plan)
                                else
                                  executor.execute execution_plan
                                end
    end

    ## world.wakeup(step_id, :finished, task)
    ## world.wakeup(step_id, :update_progress, tasks['progress'])
    #def wake_up(step_id, method, *args)
    #  @suspended_actions[step_id] # TODO tell executor to weak up the action with method(*args)
    #end
  end
end
