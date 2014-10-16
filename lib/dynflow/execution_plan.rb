require 'uuidtools'

module Dynflow

  # TODO extract planning logic to an extra class ExecutionPlanner
  class ExecutionPlan < Serializable

    include Algebrick::TypeCheck
    include Stateful

    require 'dynflow/execution_plan/steps'
    require 'dynflow/execution_plan/output_reference'
    require 'dynflow/execution_plan/dependency_graph'

    attr_reader :id, :world, :root_plan_step, :steps, :run_flow, :finalize_flow,
                :started_at, :ended_at, :execution_time, :real_time, :execution_history

    def self.states
      @states ||= [:pending, :planning, :planned, :running, :paused, :stopped]
    end

    def self.state_transitions
      @state_transitions ||= { pending:  [:planning],
                               planning: [:planned, :stopped],
                               planned:  [:running],
                               running:  [:paused, :stopped],
                               paused:   [:running],
                               stopped:  [] }
    end

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
        execution_time = nil,
        real_time = 0.0,
        execution_history = ExecutionHistory.new)

      @id                = Type! id, String
      @world             = Type! world, World
      self.state         = state
      @run_flow          = Type! run_flow, Flows::Abstract
      @finalize_flow     = Type! finalize_flow, Flows::Abstract
      @root_plan_step    = root_plan_step
      @started_at        = Type! started_at, Time, NilClass
      @ended_at          = Type! ended_at, Time, NilClass
      @execution_time    = Type! execution_time, Numeric, NilClass
      @real_time         = Type! real_time, Numeric
      @execution_history = Type! execution_history, ExecutionHistory

      steps.all? do |k, v|
        Type! k, Integer
        Type! v, Steps::Abstract
      end
      @steps = steps
    end

    def logger
      @world.logger
    end

    def update_state(state)
      original = self.state
      case self.state = state
      when :planning
        @started_at = Time.now
      when :stopped
        @ended_at       = Time.now
        @real_time      = @ended_at - @started_at
        @execution_time = compute_execution_time
      else
        # ignore
      end
      logger.debug format('%13s %s    %9s >> %9s',
                          'ExecutionPlan', id, original, state)
      self.save
    end

    def result
      all_steps = steps.values
      if all_steps.any? { |step| step.state == :error }
        return :error
      elsif all_steps.any? { |step| [:skipping, :skipped].include?(step.state) }
        return :warning
      elsif all_steps.all? { |step| step.state == :success }
        return :success
      else
        return :pending
      end
    end

    def error?
      result == :error
    end

    def errors
      steps.values.map(&:error).compact
    end

    def rescue_strategy
      Type! entry_action.rescue_strategy, Action::Rescue::Strategy
    end

    def rescue_plan_id
      case rescue_strategy
      when Action::Rescue::Pause
        nil
      when Action::Rescue::Skip
        failed_steps.each { |step| self.skip(step) }
        self.id
      end
    end

    def failed_steps
      steps_in_state(:error)
    end

    def steps_in_state(*states)
      self.steps.values.find_all {|step| states.include?(step.state) }
    end

    def rescue_from_error
      if rescue_plan_id = self.rescue_plan_id
        @world.execute(rescue_plan_id)
      else
        raise Errors::RescueError, 'Unable to rescue from the error'
      end
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
      @root_plan_step = add_plan_step(action_class)
      @root_plan_step.save
    end

    def plan(*args)
      update_state(:planning)
      world.transaction_adapter.transaction do
        world.middleware.execute(:plan_phase, root_plan_step.action_class) do
          with_planning_scope do
            root_plan_step.execute(self, nil, false, *args)

            if @dependency_graph.unresolved?
              raise "Some dependencies were not resolved: #{@dependency_graph.inspect}"
            end
          end
        end

        if @run_flow.size == 1
          @run_flow = @run_flow.sub_flows.first
        end

        world.transaction_adapter.rollback if error?
      end
      steps.values.each(&:save)
      update_state(error? ? :stopped : :planned)
    end

    def skip(step)
      steps_to_skip = steps_to_skip(step).each(&:mark_to_skip)
      self.save
      return steps_to_skip
    end

    # All the steps that need to get skipped when wanting to skip the step
    # includes the step itself, all steps dependent on it (even transitively)
    # FIND maybe move to persistence to let adapter to do it effectively?
    # @return [Array<Steps::Abstract>]
    def steps_to_skip(step)
      dependent_steps = steps.values.find_all do |s|
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
      return block.call
    ensure
      @run_flow_stack.pop
      current_run_flow.add_and_resolve(@dependency_graph, new_flow) if current_run_flow
    end

    def add_plan_step(action_class, planned_by = nil)
      add_step(Steps::PlanStep, action_class, generate_action_id, planned_by && planned_by.plan_step_id).tap do |step|
        step.initialize_action
      end
    end

    def add_run_step(action)
      add_step(Steps::RunStep, action.class, action.id).tap do |step|
        step.progress_weight = action.run_progress_weight
        @dependency_graph.add_dependencies(step, action)
        current_run_flow.add_and_resolve(@dependency_graph, Flows::Atom.new(step.id))
      end
    end

    def add_finalize_step(action)
      add_step(Steps::FinalizeStep, action.class, action.id).tap do |step|
        step.progress_weight = action.finalize_progress_weight
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
                        step_ids:          steps.map { |id, _| id },
                        started_at:        time_to_str(started_at),
                        ended_at:          time_to_str(ended_at),
                        execution_time:    execution_time,
                        real_time:         real_time,
                        execution_history: execution_history.to_hash
    end

    def save
      persistence.save_execution_plan(self)
    end

    def self.new_from_hash(hash, world)
      check_class_matching hash
      execution_plan_id = hash[:id]
      steps             = steps_from_hash(hash[:step_ids], execution_plan_id, world)
      self.new(world,
               execution_plan_id,
               hash[:state],
               steps[hash[:root_plan_step_id]],
               Flows::Abstract.from_hash(hash[:run_flow]),
               Flows::Abstract.from_hash(hash[:finalize_flow]),
               steps,
               string_to_time(hash[:started_at]),
               string_to_time(hash[:ended_at]),
               hash[:execution_time].to_f,
               hash[:real_time].to_f,
               ExecutionHistory.new_from_hash(hash[:execution_history]))
    end

    def compute_execution_time
      self.steps.values.reduce(0) do |execution_time, step|
        execution_time + (step.execution_time || 0)
      end
    end

    # @return [0..1] the percentage of the progress. See Action::Progress for more
    # info
    def progress
      flow_step_ids         = run_flow.all_step_ids + finalize_flow.all_step_ids
      plan_done, plan_total = flow_step_ids.reduce([0.0, 0]) do |(done, total), step_id|
        step = self.steps[step_id]
        [done + (step.progress_done * step.progress_weight),
         total + step.progress_weight]
      end
      plan_total > 0 ? (plan_done / plan_total) : 1
    end

    def entry_action
      @entry_action ||= root_plan_step.action(self)
    end

    # @return [Array<Action>] actions in Present phase
    def actions
      @actions ||= begin
        [entry_action] + entry_action.all_planned_actions
      end
    end

    private

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
