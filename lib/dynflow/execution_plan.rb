require 'uuidtools'

module Dynflow

  # TODO extract planning logic to an extra class ExecutionPlanner
  class ExecutionPlan < Serializable
    include Algebrick::TypeCheck

    require 'dynflow/execution_plan/steps'
    require 'dynflow/execution_plan/output_reference'
    require 'dynflow/execution_plan/dependency_graph'

    attr_reader :id, :world, :state, :root_plan_step, :steps, :run_flow, :finalize_flow,
                :started_at, :ended_at, :execution_time, :real_time

    STATES            = [:pending, :running, :paused, :stopped]
    STATE_TRANSITIONS = { pending: [:running, :stopped],
                          running: [:paused, :stopped],
                          paused:  [:running],
                          stopped: [] }

    # all params with default values are part of *private* api
    def initialize(world,
        id = UUIDTools::UUID.random_create.to_s,
        state = :pending,
        root_plan_step = nil,
        run_flow = Flows::Concurrence.new([]),
        finalize_flow = Flows::Sequence.new([]),
        steps = {},
        started_at = nil,
        ended_at = nil,
        execution_time = 0.0,
        real_time = 0.0)

      @id             = is_kind_of! id, String
      @world          = is_kind_of! world, World
      self.state      = state
      @run_flow       = is_kind_of! run_flow, Flows::Abstract
      @finalize_flow  = is_kind_of! finalize_flow, Flows::Abstract
      @root_plan_step = root_plan_step
      @started_at     = is_kind_of! started_at, Time, NilClass
      @ended_at       = is_kind_of! ended_at, Time, NilClass
      @execution_time = is_kind_of! execution_time, Float
      @real_time      = is_kind_of! real_time, Float

      steps.all? do |k, v|
        is_kind_of! k, Integer
        is_kind_of! v, Steps::Abstract
      end
      @steps = steps
    end

    def set_state(state)
      unless STATE_TRANSITIONS[self.state].include?(state)
        raise "invalid state transition #{self.state} >> #{state}"
      end
      case state
      when :stopped
        @ended_at  = Time.now
        @real_time = @ended_at - @started_at
      end
      self.state = state
      self.save
    end

    def update_meta_data(execution_time)
      # TODO cleanup ? this method is called allover the place
      @execution_time += execution_time
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
      @root_plan_step = add_step(Steps::PlanStep, action_class, generate_action_id)
    end

    def plan(*args)
      @started_at = Time.now
      world.transaction_adapter.transaction do
        with_planning_scope do
          root_plan_step.execute(self, nil, *args)

          if @dependency_graph.unresolved?
            raise "Some dependencies were not resolved: #{@dependency_graph.inspect}"
          end
        end

        if @run_flow.size == 1
          @run_flow = @run_flow.sub_flows.first
        end

        world.transaction_adapter.rollback if error?
      end
      set_state(:stopped) if error?
      save
      steps.values.each &:save
    end

    def skip(step)
      raise "plan step can't be skipped" if step.is_a? Steps::PlanStep
      steps_to_skip = steps_to_skip(step).each do |s|
        s.state = :skipped
        s.save
      end
      self.save
      return steps_to_skip
    end

    # All the steps that need to get skipped when wanting to skip the step
    # includes the step itself, all steps dependent on it (even transitively)
    # FIND maybe move to persistence to let adapter to do it effectively?
    # @return [Array<Steps::Abstract>]
    def steps_to_skip(step)
      dependent_steps = @steps.values.find_all do |s|
        next if s.is_a? Steps::PlanStep
        action = persistence.load_action(s)
        action.required_step_ids.include?(step.id)
      end

      steps_to_skip = dependent_steps.map do |dependent_step|
        steps_to_skip(dependent_step)
      end.flatten

      steps_to_skip << step

      if step.is_a? Steps::RunStep
        finalize_step_id = persistence.load_action(step).finalize_step_id
        steps_to_skip << steps[finalize_step_id] if finalize_step_id
      end

      return steps_to_skip.uniq
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
      add_step(Steps::PlanStep, action_class, generate_action_id, planned_by.plan_step_id)
    end

    def add_run_step(action)
      add_step(Steps::RunStep, action.action_class, action.id).tap do |step|
        @dependency_graph.add_dependencies(step, action)
        current_run_flow.add_and_resolve(@dependency_graph, Flows::Atom.new(step.id))
      end
    end

    def add_finalize_step(action)
      add_step(Steps::FinalizeStep, action.action_class, action.id).tap do |step|
        finalize_flow << Flows::Atom.new(step.id)
      end
    end

    def to_hash
      recursive_to_hash id:                self.id,
                        class:             self.class.to_s,
                        state:             self.state,
                        result:            result,
                        root_plan_step_id: root_plan_step && root_plan_step.id,
                        run_flow:          run_flow,
                        finalize_flow:     finalize_flow,
                        steps:             steps.map { |id, _| id },
                        started_at:        time_to_str(started_at),
                        ended_at:          time_to_str(ended_at),
                        execution_time:    execution_time,
                        real_time:         real_time
    end

    def save
      persistence.save_execution_plan(self)
    end

    def self.new_from_hash(hash, world)
      check_class_matching hash
      execution_plan_id = hash[:id]
      # TODO do not load all steps with the EP, lazy load when needed
      steps             = steps_from_hash(hash[:steps], execution_plan_id, world)
      self.new(world,
               execution_plan_id,
               hash[:state],
               steps[hash[:root_plan_step_id]],
               Flows::Abstract.from_hash(hash[:run_flow]),
               Flows::Abstract.from_hash(hash[:finalize_flow]),
               steps,
               string_to_time(hash[:started_at]),
               string_to_time(hash[:ended_at]),
               hash[:execution_time],
               hash[:real_time])
    end

    # @return [0..1] the percentage of the progress. See Action::Progress for more
    # info
    def progress
      flow_step_ids = run_flow.all_step_ids + finalize_flow.all_step_ids
      plan_done, plan_total = flow_step_ids.reduce([0.0 ,0]) do |(done, total), step_id|
        step_progress_done, step_progress_weight = self.steps[step_id].progress
        [done + (step_progress_done * step_progress_weight),
         total + step_progress_weight]
      end
      plan_total > 0 ? (plan_done / plan_total) : 1
    end

    private

    def state=(state)
      if state.is_a?(String) && STATES.map(&:to_s).include?(state)
        @state = state.to_sym
      elsif STATES.include? state
        @state = state
      else
        raise "unknown state #{state}"
      end
    end

    def persistence
      world.persistence
    end

    def add_step(step_class, action_class, action_id, planned_by_step_id = nil)
      step_class.new(self.id,
                     self.generate_step_id,
                     :pending,
                     action_class,
                     action_id,
                     nil,
                     world).tap do |new_step|
        @steps[new_step.id] = new_step
        @steps[planned_by_step_id].children << new_step.id if planned_by_step_id
      end
    end

    def self.steps_from_hash(step_ids, execution_plan_id, world)
      step_ids.inject({}) do |hash, step_id|
        step = world.persistence.load_step(execution_plan_id, step_id, world)
        hash.update(step_id.to_i => step)
      end
    end

    private_class_method :steps_from_hash
  end
end
