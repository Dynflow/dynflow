require 'securerandom'

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
      @states ||= [:pending, :scheduled, :planning, :planned, :running, :paused, :stopped]
    end

    def self.results
      @results ||= [:pending, :success, :warning, :error]
    end

    def self.state_transitions
      @state_transitions ||= { pending:  [:stopped, :scheduled, :planning],
                               scheduled: [:planning, :stopped],
                               planning: [:planned, :stopped],
                               planned:  [:running, :stopped],
                               running:  [:paused, :stopped],
                               paused:   [:running, :stopped],
                               stopped:  [] }
    end

    # all params with default values are part of *private* api
    def initialize(world,
                   id                = SecureRandom.uuid,
                   state             = :pending,
                   root_plan_step    = nil,
                   run_flow          = Flows::Concurrence.new([]),
                   finalize_flow     = Flows::Sequence.new([]),
                   steps             = {},
                   started_at        = nil,
                   ended_at          = nil,
                   execution_time    = nil,
                   real_time         = 0.0,
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
        @real_time      = @ended_at - @started_at unless @started_at.nil?
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

    def error_in_plan?
      steps_in_state(:error).any? { |step| step.is_a? Steps::PlanStep }
    end

    def errors
      steps.values.map(&:error).compact
    end

    def rescue_strategy
      Type! entry_action.rescue_strategy, Action::Rescue::Strategy
    end

    def sub_plans
      persistence.find_execution_plans(filters: { 'caller_execution_plan_id' => self.id })
    end

    def rescue_plan_id
      case rescue_strategy
      when Action::Rescue::Pause
        nil
      when Action::Rescue::Fail
        update_state :stopped
        nil
      when Action::Rescue::Skip
        failed_steps.each { |step| self.skip(step) }
        self.id
      end
    end

    def plan_steps
      steps_of_type(Dynflow::ExecutionPlan::Steps::PlanStep)
    end

    def run_steps
      steps_of_type(Dynflow::ExecutionPlan::Steps::RunStep)
    end

    def finalize_steps
      steps_of_type(Dynflow::ExecutionPlan::Steps::FinalizeStep)
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

    def delay(caller_action, action_class, delay_options, *args)
      save
      @root_plan_step = add_scheduling_step(action_class, caller_action)
      execution_history.add("delay", @world.id)
      serializer = root_plan_step.delay(delay_options, args)
      delayed_plan = DelayedPlan.new(@world,
                                     id,
                                     delay_options[:start_at],
                                     delay_options.fetch(:start_before, nil),
                                     serializer)
      persistence.save_delayed_plan(delayed_plan)
    ensure
      update_state(error? ? :stopped : :scheduled)
    end

    def delay_record
      @delay_record ||= persistence.load_delayed_plan(id)
    end

    def prepare(action_class, options = {})
      options = options.dup
      caller_action = Type! options.delete(:caller_action), Dynflow::Action, NilClass
      raise "Unexpected options #{options.keys.inspect}" unless options.empty?
      save
      @root_plan_step = add_plan_step(action_class, caller_action)
      @root_plan_step.save
    end

    def plan(*args)
      update_state(:planning)
      world.middleware.execute(:plan_phase, root_plan_step.action_class, self) do
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
      steps.values.each(&:save)
      update_state(error? ? :stopped : :planned)
    end

    # sends the cancel event to all currently running and cancellable steps.
    # if the plan is just scheduled, it cancels it (and returns an one-item
    # array with the future value of the cancel result)
    def cancel
      if state == :scheduled
        [Concurrent.future.tap { |f| f.success delay_record.cancel }]
      else
        steps_to_cancel.map do |step|
          world.event(id, step.id, ::Dynflow::Action::Cancellable::Cancel)
        end
      end
    end

    def cancellable?
      return true if state == :scheduled
      return false unless state == :running
      steps_to_cancel.any?
    end

    def steps_to_cancel
      steps_in_state(:running, :suspended).find_all do |step|
        step.action(self).is_a?(::Dynflow::Action::Cancellable)
      end
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

    def steps_of_type(type)
      steps.values.find_all { |step| step.is_a?(type) }
    end

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

    def add_scheduling_step(action_class, caller_action = nil)
      add_step(Steps::PlanStep, action_class, generate_action_id, :scheduling).tap do |step|
        step.initialize_action(caller_action)
      end
    end

    def add_plan_step(action_class, caller_action = nil)
      add_step(Steps::PlanStep, action_class, generate_action_id).tap do |step|
        # TODO: to be removed and preferred by the caller_action
        if caller_action && caller_action.execution_plan_id == self.id
          @steps[caller_action.plan_step_id].children << step.id
        end
        step.initialize_action(caller_action)
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
      return 0 if [:pending, :planning, :scheduled].include?(state)
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

    def caller_execution_plan_id
      entry_action.caller_execution_plan_id
    end

    private

    def persistence
      world.persistence
    end

    def add_step(step_class, action_class, action_id, state = :pending)
      step_class.new(self.id,
                     self.generate_step_id,
                     state,
                     action_class,
                     action_id,
                     nil,
                     world).tap do |new_step|
        @steps[new_step.id] = new_step
      end
    end

    def self.steps_from_hash(step_ids, execution_plan_id, world)
      steps = world.persistence.load_steps(execution_plan_id, world)
      ids_to_steps = steps.inject({}) do |hash, step|
        hash[step.id.to_i] = step
        hash
      end
      # to make sure to we preserve the order of the steps
      step_ids.inject({}) do |hash, step_id|
        hash[step_id.to_i] = ids_to_steps[step_id.to_i]
        hash
      end
    end

    private_class_method :steps_from_hash
  end
end
