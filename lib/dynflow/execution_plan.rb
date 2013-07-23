module Dynflow
  class ExecutionPlan < Serializable
    include Algebrick::TypeCheck

    require 'dynflow/execution_plan/steps'

    attr_reader :id, :world, :plan_steps

    def initialize(world, action_class)
      @id                   = rand(1e10).to_s(36) # TODO replace with uuid?
      @world                = is_kind_of! world, World
      @planning_scope_stack = []
      prepare(action_class)

      @plan_steps = {}
    end

    def generate_action_id
      @last_action_id ||= 0
      @last_action_id += 1
    end

    def generate_step_id
      @last_step_id ||= 0
      @last_step_id += 1
    end

    def plan(*args)
      root_plan_step.execute(*args)
    end

    # @api private
    def with_planning_scope(&block)
      switch_scope Concurrence, &block
    end

    # @api private
    def switch_scope(scope_class, &block)
      @planning_scope_stack << scope_class.new
      block.call
    ensure
      @planning_scope_stack.pop
    end

    def add_plan_step(action_class, planned_by)
      new_plan_step(generate_step_id, action_class, generate_action_id, planned_by.id)
    end

    def add_run_step(action)
      @planning_scope_stack.last << action # FIXME
    end

    def add_finalize_step(action)
    end

    def to_hash
      # TODO
    end

    private

    def prepare(action_class)
      persistence_adapter.save_execution_plan self.to_hash
      new_plan_step generate_step_id, action_class, generate_action_id
    end

    def new_plan_step(id, action_class, action_id, planned_by_step_id = nil)
      @plan_steps[id] = step = Steps::Planning.new(self, id, :pending, action_class, action_id)
      @plan_steps[planned_by_step_id].children << step.id if planned_by_step_id
      step
    end
  end
end
