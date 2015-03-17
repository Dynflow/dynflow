require 'dynflow/persistence_adapters'

module Dynflow

  class Persistence

    include Algebrick::TypeCheck

    attr_reader :adapter

    def initialize(world, persistence_adapter)
      @world   = world
      @adapter = persistence_adapter
      @adapter.register_world(world)
    end

    def load_action(step)
      attributes = adapter.
          load_action(step.execution_plan_id, step.action_id).
          update(step: step, phase: step.phase)
      return Action.from_hash(attributes, step.world)
    end

    def load_action_for_presentation(execution_plan, action_id)
      attributes = adapter.load_action(execution_plan.id, action_id)
      Action.from_hash(attributes.update(phase: Action::Present, execution_plan: execution_plan), @world)
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

    def push_envelope(envelope)
      Type! envelope, Dispatcher::Envelope
      adapter.push_envelope(Dynflow.serializer.dump(envelope))
    end

    def pull_envelopes(world_id)
      adapter.pull_envelopes(world_id).map do |data|
        envelope = Dynflow.serializer.load(data)
        Type! envelope, Dispatcher::Envelope
        envelope
      end
    end
  end
end
