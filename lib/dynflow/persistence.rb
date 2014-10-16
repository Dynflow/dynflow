require 'dynflow/persistence_adapters'

module Dynflow

  class Persistence

    include Algebrick::TypeCheck

    attr_reader :adapter

    def initialize(world, persistence_adapter)
      @world   = world
      @adapter = persistence_adapter
    end

    def load_action(step)
      attributes = adapter.
          load_action(step.execution_plan_id, step.action_id).
          update(step: step, phase: step.phase)
      return Action.from_hash(attributes, step.world)
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

    RegisteredWorld = Algebrick.type do
      fields! id:       String,
              executor: type { variants TrueClass, FalseClass }
    end

    ExecutorAllocation = Algebrick.type do
      fields! world_id: String,
              execution_plan_id: String
    end

    def find_worlds(options)
      adapter.find_worlds(options)
    end

    def save_world(world)
      Type! world, RegisteredWorld
      adapter.save_world(world.id, world.to_hash)
    end

    def delete_world(world)
      Type! world, RegisteredWorld
      adapter.transaction do
        pull_envelopes(world.id)
        adapter.delete_executor_allocations(world_id: world.id)
        adapter.delete_world(world.id)
      end
    end

    def find_executor_for_plan(execution_plan_id)
      allocation = find_executor_allocations(filters: { execution_plan_id: execution_plan_id }).first
      if allocation
        return RegisteredWorld[allocation.world_id, true]
      end
    end

    def find_executor_allocations(options)
      adapter.find_executor_allocations(options)
    end

    def save_executor_allocation(executor_allocation)
      Type! executor_allocation, ExecutorAllocation
      adapter.save_executor_allocation(executor_allocation)
    end

    def delete_executor_allocation(executor_allocation)
      Type! executor_allocation, ExecutorAllocation
      adapter.delete_executor_allocations(world_id: executor_allocation.world_id,
                                          execution_plan_id: executor_allocation.execution_plan_id)
    end

    def push_envelope(envelope)
      Type! envelope, Dispatcher::Envelope
      adapter.push_envelope(envelope)
    end

    def pull_envelopes(world_id)
      adapter.pull_envelopes(world_id)
    end
  end
end
