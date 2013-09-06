require 'dynflow/persistence_adapters'

module Dynflow

  # TODO add and store metadata for actions and execution_plan
  # TODO filter/order by metadata
  # TODO pagination
  # e.g. start_time, end_time, run_time duration, statuses

  class Persistence

    attr_reader :adapter

    def initialize(world, persistence_adapter)
      @world   = world
      @adapter = persistence_adapter
    end

    def load_action(step)
      attributes = adapter.load_action(step.execution_plan_id, step.action_id)
      return Action.from_hash(attributes,
                              step.phase,
                              step.state,
                              step.world)
    end

    def save_action(step, action)
      adapter.save_action(step.execution_plan_id, step.action_id, action.to_hash)
    end

    def find_execution_plans
      # TODO: add filtering and pagination
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
