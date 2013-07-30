module Dynflow
  class ExecutionPlan < Serializable
    include Algebrick::TypeCheck

    require 'dynflow/execution_plan/steps'
    require 'dynflow/execution_plan/output_reference'
    require 'dynflow/execution_plan/dependency_graph'

    attr_reader :id, :world, :root_plan_step, :plan_steps, :run_flow, :run_steps

    # all params with default values are part of *private* api
    # TODO replace id with uuid?
    def initialize(world,
        id = rand(1e10).to_s(36),
        root_plan_step = nil,
        run_flow = Flows::Concurrence.new([]),
        plan_steps = {},
        run_steps = {})

      @id    = is_kind_of! id, String
      @world = is_kind_of! world, World


      @run_flow       = is_kind_of! run_flow, Flows::Abstract
      @root_plan_step = root_plan_step

      plan_steps.all? do |k, v|
        is_kind_of! k, Integer
        is_kind_of! v, Steps::PlanStep
      end
      @plan_steps = plan_steps

      run_steps.all? do |k, v|
        is_kind_of! k, Integer
        is_kind_of! v, Steps::RunStep
      end
      @run_steps = run_steps
    end

    def result
      # fail in planning phase: we don't care about the rest
      if @plan_steps.values.any? { |step| step.state == :error }
        return :error
      end

      all_steps = run_flow.all_step_ids.map { |id| run_steps[id] }
      if all_steps.any? { |step| step.state == :error }
        return :error
      elsif all_steps.all? { |step| [:success, :skipped].include?(step.state) }
        return :success
      else
        return :pending
      end
    end

    def error?
      result == :error
    end

    def generate_action_id
      @last_action_id ||= 0
      @last_action_id += 1
    end

    def generate_step_id
      @last_step_id ||= 0
      @last_step_id += 1
    end

    def prepare(action_class)
      save
      @root_plan_step = new_plan_step(generate_step_id, action_class, generate_action_id)
    end

    def plan(*args)
      with_planning_scope do
        root_plan_step.execute(nil, *args)

        if @dependency_graph.unresolved?
          raise "Some dependencies were not resolved: #{@dependency_graph.inspect}"
        end
      end

      if @run_flow.size == 1
        @run_flow = @run_flow.sub_flows.first
      end
      save
    end

    # @api private
    def current_run_flow
      @run_flow_stack.last
    end

    # @api private
    def with_planning_scope(&block)
      @run_flow_stack   = []
      @dependency_graph = DependencyGraph.new
      switch_flow(run_flow, &block)
    ensure
      @run_flow_stack   = nil
      @dependency_graph = nil
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
      run_step = Steps::RunStep.new(self.id,
                                    self.generate_step_id,
                                    :pending,
                                    action.action_class,
                                    action.id,
                                    world)
      @dependency_graph.add_dependencies(run_step, action.input)
      current_run_flow.add_and_resolve(@dependency_graph, Flows::Atom.new(run_step.id))
      @run_steps[run_step.id] = run_step
      return run_step
    end

    def add_finalize_step(action)
    end

    def to_hash
      values_to_hash = lambda { |h, (id, step)| h.update(id => step.to_hash) }
      { id:                self.id,
        class:             self.class.to_s,
        root_plan_step_id: root_plan_step && root_plan_step.id,
        run_flow:          run_flow.to_hash,
        plan_steps:        plan_steps.inject({}, &values_to_hash),
        run_steps:         run_steps.inject({}, &values_to_hash) }
    end

    def save
      persistence.save_execution_plan(self)
    end

    def self.new_from_hash(hash, world)
      check_class_matching hash
      execution_plan_id = hash[:id]
      instance          = allocate
      plan_steps        = steps_from_hash(hash[:plan_steps], execution_plan_id, world, instance)

      instance.send(:initialize,
                    world,
                    execution_plan_id,
                    plan_steps[hash[:root_plan_step_id]],
                    Flows::Abstract.from_hash(hash[:run_flow]),
                    plan_steps,
                    steps_from_hash(hash[:run_steps], execution_plan_id, world))

      return instance
    end

    private

    def persistence
      world.persistence
    end

    def new_plan_step(id, action_class, action_id, planned_by_step_id = nil)
      @plan_steps[id] = step = Steps::PlanStep.new(self.id, id, :pending, action_class, action_id, world, self)
      @plan_steps[planned_by_step_id].children << step.id if planned_by_step_id
      step
    end

    def self.plan_steps_from_hash(plan_steps_hash, execution_plan_id, world, execution_plan)
      plan_steps_hash.reduce({}) do |h, (id, step_hash)|
        h.update(id.to_i => Steps::PlanStep.from_hash(step_hash, execution_plan_id, world, execution_plan))
      end
    end

    def self.steps_from_hash(hash, execution_plan_id, world, instance = nil)
      hash.inject({}) do |h, (step_id, step_hash)|
        args = [step_hash, execution_plan_id, world, instance].compact
        h.update(step_id.to_i => Steps::Abstract.from_hash(*args))
      end
    end

    private_class_method :plan_steps_from_hash
  end
end
