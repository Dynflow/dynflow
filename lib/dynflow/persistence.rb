require 'dynflow/persistence_adapters'

module Dynflow
  class Persistence

    attr_reader :adapter

    def initialize(world, persistence_adapter)
      @world   = world
      @adapter = persistence_adapter
    end

    def load_step_action(step)
      attributes = adapter.load_action(step.execution_plan.id, step.action_id)
      return Action.from_hash(attributes,
                              step.phase,
                              step.state,
                              step.id,
                              step.execution_plan.world)
    end

    def save_step_action(step, action)
      adapter.save_action(step.execution_plan.id, step.action_id, action.to_hash)
    end

    def load_execution_plans
      adapter.find_execution_plans.map do |execution_plan_hash|
        ExecutionPlan.new_from_hash(execution_plan_hash, @world)
      end
    end

    def load_execution_plan(id)
      execution_plan_hash = adapter.load_execution_plan(id)
      ExecutionPlan.new_from_hash(execution_plan_hash, @world)
    end

    def save_execution_plan(execution_plan)
      adapter.save_execution_plan(execution_plan.id, execution_plan.to_hash)
    end

  end
end
