require 'dynflow/persistence_adapters'

module Dynflow

  class Persistence

    attr_reader :adapter

    def initialize(world, persistence_adapter)
      @world   = world
      @adapter = persistence_adapter
    end

    def load_action(step)
      attributes = adapter.
          load_action(step.execution_plan_id, step.action_id).
          update(step: step)
      return Action.from_hash(attributes,
                              step.phase,
                              step,
                              step.world)
    end

    def save_action(execution_plan_id, action)
      adapter.save_action(execution_plan_id, action.id, action.to_hash)
    end

    def find_execution_plans(options)
      adapter.find_execution_plans(options).map do |execution_plan_hash|
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

    def load_step(execution_plan_id, step_id, world)
      step_hash = adapter.load_step(execution_plan_id, step_id)
      ExecutionPlan::Steps::Abstract.from_hash(step_hash, execution_plan_id, world)
    end

    def save_step(step)
      adapter.save_step(step.execution_plan_id, step.id, step.to_hash)
    end

  end
end
