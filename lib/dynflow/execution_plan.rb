module Dynflow
  class ExecutionPlan < Serializable
    include Algebrick::TypeCheck

    require 'dynflow/execution_plan/steps'
    require 'dynflow/execution_plan/output_reference'
    require 'dynflow/execution_plan/dependency_graph'

    attr_reader :id, :world, :state, :root_plan_step, :steps, :run_flow, :finalize_flow

    STATES = [:pending, :running, :paused, :stopped]

    # all params with default values are part of *private* api
    # TODO replace id with uuid?
    def initialize(world,
                   id             = rand(1e10).to_s(36),
                   state          = :pending,
                   root_plan_step = nil,
                   run_flow       = Flows::Concurrence.new([]),
                   finalize_flow  = Flows::Sequence.new([]),
                   steps          = {})

      @id    = is_kind_of! id, String
      @world = is_kind_of! world, World
      self.state      = state
      @run_flow       = is_kind_of! run_flow, Flows::Abstract
      @finalize_flow  = is_kind_of! finalize_flow, Flows::Abstract
      @root_plan_step = root_plan_step

      steps.all? do |k, v|
        is_kind_of! k, Integer
        is_kind_of! v, Steps::Abstract
      end
      @steps = steps

    end

    def state=(state)
      if state.is_a?(String) && STATES.map(&:to_s).include?(state)
        @state = state.to_sym
      elsif STATES.include? state
        @state = state
      else
        raise "unknown state #{state}"
      end
    end

    def result
      all_steps = steps.values
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
        root_plan_step.execute(self, nil, *args)

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
      add_step(Steps::RunStep, action).tap do |step|
        @dependency_graph.add_dependencies(step, action.input)
        current_run_flow.add_and_resolve(@dependency_graph, Flows::Atom.new(step.id))
      end
    end

    def add_finalize_step(action)
      add_step(Steps::FinalizeStep, action).tap do |step|
        finalize_flow << Flows::Atom.new(step.id)
      end
    end

    def to_hash
      { id:                self.id,
        class:             self.class.to_s,
        state:             self.state,
        root_plan_step_id: root_plan_step && root_plan_step.id,
        run_flow:          run_flow.to_hash,
        finalize_flow:     finalize_flow.to_hash,
        steps:             steps.inject({}) { |h, (id, step)| h.update(id => step.to_hash) } }
    end

    def save
      persistence.save_execution_plan(self)
    end

    def self.new_from_hash(hash, world)
      check_class_matching hash
      execution_plan_id = hash[:id]
      steps = steps_from_hash(hash[:steps], execution_plan_id, world)
      self.new(world,
               execution_plan_id,
               hash[:state],
               steps[hash[:root_plan_step_id]],
               Flows::Abstract.from_hash(hash[:run_flow]),
               Flows::Abstract.from_hash(hash[:finalize_flow]),
               steps)
    end

    private

    def persistence
      world.persistence
    end

    def new_plan_step(id, action_class, action_id, planned_by_step_id = nil)
      @steps[id] = step = Steps::PlanStep.new(self.id, id, :pending, action_class, action_id, world)
      @steps[planned_by_step_id].children << step.id if planned_by_step_id
      step
    end

    def add_step(step_class, action)
      step_class.new(self.id,
                     self.generate_step_id,
                     :pending,
                     action.action_class,
                     action.id,
                     world).tap do |new_step|
        @steps[new_step.id] = new_step
      end
    end

    def self.steps_from_hash(hash, execution_plan_id, world)
      hash.inject({}) do |h, (step_id, step_hash)|
        step = Steps::Abstract.from_hash(step_hash, execution_plan_id, world)
        h.update(step_id.to_i => step)
      end
    end

    private_class_method :steps_from_hash
  end
end
