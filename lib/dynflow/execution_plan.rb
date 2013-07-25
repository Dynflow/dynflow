module Dynflow
  class ExecutionPlan < Serializable
    include Algebrick::TypeCheck

    require 'dynflow/execution_plan/steps'
    require 'dynflow/execution_plan/output_reference'
    require 'dynflow/execution_plan/dependency_graph'

    attr_reader :id, :world, :root_plan_step, :plan_steps, :run_flow

    def initialize(world, action_class)
      @id               = rand(1e10).to_s(36) # TODO replace with uuid?
      @world            = is_kind_of! world, World
      @plan_steps       = {}

      @run_flow         = Flows::Concurrence.new([])
      @run_flow_stack   = []
      @root_plan_step   = nil
      @dependency_graph = DependencyGraph.new

      prepare(action_class)
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
      with_planning_scope do
        root_plan_step.execute(nil, *args)
      end

      if @dependency_graph.unresolved?
        raise "Some dependencies were not resolved: #{@dependency_graph.inspect}"
      end

      if @run_flow.size == 1
        @run_flow = @run_flow.sub_flows.first
      end
    end

    # @api private
    def current_run_flow
      @run_flow_stack.last
    end

    # @api private
    def with_planning_scope(&block)
      switch_flow(run_flow, &block)
    end

    # @api private
    # Switches the flow type (Sequence, Concurrence) to be used within the block.
    def switch_flow(new_flow, &block)
      @run_flow_stack << new_flow
      block.call
      return new_flow
    ensure
      @run_flow_stack.pop
      current_run_flow.add_and_resolve(@dependency_graph, new_flow) if current_run_flow
    end

    def add_plan_step(action_class, planned_by)
      new_plan_step(generate_step_id, action_class, generate_action_id, planned_by.plan_step_id)
    end

    def add_run_step(action)
      run_step = Steps::RunStep.new(self,
                                    self.generate_step_id,
                                    :pending,
                                    action.class,
                                    action.id)
      @dependency_graph.add_dependencies(run_step, action.input)
      current_run_flow.add_and_resolve(@dependency_graph, Flows::Atom.new(run_step))
      return run_step
    end

    def add_finalize_step(action)
    end

    def to_hash
      { 'plan_steps' => @plan_steps.map(&:to_hash) }
    end

    private

    def persistence_adapter
      world.persistence_adapter
    end

    def prepare(action_class)
      persistence_adapter.save_execution_plan(self.id, self.to_hash)
      @root_plan_step = new_plan_step(generate_step_id, action_class, generate_action_id)
    end

    def new_plan_step(id, action_class, action_id, planned_by_step_id = nil)
      @plan_steps[id] = step = Steps::PlanStep.new(self, id, :pending, action_class, action_id)
      @plan_steps[planned_by_step_id].children << step.id if planned_by_step_id
      step
    end
  end
end
