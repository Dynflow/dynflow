module Dynflow
  class Action < Serializable

    OutputReference = ExecutionPlan::OutputReference

    include Algebrick::TypeCheck
    include Algebrick::Matching

    require 'dynflow/action/format'
    extend Action::Format

    require 'dynflow/action/progress'
    include Action::Progress

    require 'dynflow/action/rescue'
    include Action::Rescue

    require 'dynflow/action/suspended'
    require 'dynflow/action/missing'

    require 'dynflow/action/polling'
    require 'dynflow/action/cancellable'
    require 'dynflow/action/with_sub_plans'

    def self.all_children
      children.values.inject(children.values) do |children, child|
        children + child.all_children
      end
    end

    def self.inherited(child)
      children[child.name] = child
      super child
    end

    def self.children
      @children ||= {}
    end

    def self.middleware
      @middleware ||= Middleware::Register.new
    end

    # FIND define subscriptions in world independent on action's classes,
    #   limited only by in/output formats
    # @return [nil, Class] a child of Action
    def self.subscribe
      nil
    end

    ERROR   = Object.new
    SUSPEND = Object.new
    Skip    = Algebrick.atom
    Phase   = Algebrick.type do
      Executable = type do
        variants Plan     = atom,
                 Run      = atom,
                 Finalize = atom
      end
      variants Executable, Present = atom
    end

    module Executable
      def execute_method_name
        match self,
              (on Plan, :execute_plan),
              (on Run, :execute_run),
              (on Finalize, :execute_finalize)
      end
    end

    module Phase
      def to_s_humanized
        to_s.split('::').last
      end
    end

    def self.constantize(action_name)
      super action_name
    rescue NameError
      Action::Missing.generate(action_name)
    end

    attr_reader :world, :phase, :execution_plan_id, :id, :input,
                :plan_step_id, :run_step_id, :finalize_step_id,
                :caller_execution_plan_id, :caller_action_id

    middleware.use Action::Progress::Calculate

    def initialize(attributes, world)
      Type! attributes, Hash

      @phase             = Type! attributes.fetch(:phase), Phase
      @world             = Type! world, World
      @step              = Type! attributes.fetch(:step, nil), ExecutionPlan::Steps::Abstract, NilClass
      raise ArgumentError, 'Step reference missing' if phase?(Executable) && @step.nil?
      @execution_plan_id = Type! attributes.fetch(:execution_plan_id), String
      @id                = Type! attributes.fetch(:id), Integer
      @plan_step_id      = Type! attributes.fetch(:plan_step_id), Integer
      @run_step_id       = Type! attributes.fetch(:run_step_id), Integer, NilClass
      @finalize_step_id  = Type! attributes.fetch(:finalize_step_id), Integer, NilClass

      @execution_plan    = Type!(attributes.fetch(:execution_plan), ExecutionPlan) if phase? Present

      @caller_execution_plan_id  = Type!(attributes.fetch(:caller_execution_plan_id, nil), String, NilClass)
      @caller_action_id          = Type!(attributes.fetch(:caller_action_id, nil), Integer, NilClass)

      getter =-> key, required do
        required ? attributes.fetch(key) : attributes.fetch(key, {})
      end

      @input  = OutputReference.deserialize getter.(:input, phase?(Run, Finalize, Present))
      @output = OutputReference.deserialize getter.(:output, false) if phase? Run, Finalize, Present
    end

    def phase?(*phases)
      Match? phase, *phases
    end

    def phase!(*phases)
      phase?(*phases) or
        raise TypeError, "Wrong phase #{phase}, required #{phases}"
    end

    def input=(hash)
      Type! hash, Hash
      phase! Plan
      @input = Utils.indifferent_hash(hash)
    end

    def output=(hash)
      Type! hash, Hash
      phase! Run
      @output = Utils.indifferent_hash(hash)
    end

    def output
      if phase? Plan
        @output_reference or
          raise 'plan_self has to be invoked before being able to reference the output'
      else
        @output
      end
    end

    def caller_action
      plase! Present
      return nil if @caller_action_id
      return @caller_action if @caller_action

      caller_execution_plan = if @caller_execution_plan_id == execution_plan.id
                                execution_plan
                              else
                                world.persistence.load_execution_plan(@caller_execution_plan_id)
                              end
      @caller_action = world.persistence.load_action_for_presentation(caller_execution_plan, @caller_action_id)
    end

    def set_plan_context(execution_plan, trigger, from_subscription)
      phase! Plan
      @execution_plan    = Type! execution_plan, ExecutionPlan
      @trigger           = Type! trigger, Action, NilClass
      @from_subscription = Type! from_subscription, TrueClass, FalseClass
    end

    def trigger
      phase! Plan
      @trigger
    end

    def from_subscription?
      phase! Plan
      @from_subscription
    end

    def execution_plan
      phase! Plan, Present
      @execution_plan
    end

    def action_logger
      phase! Executable
      world.action_logger
    end

    def plan_step
      phase! Present
      execution_plan.steps.fetch(plan_step_id)
    end

    # @param [Class] filter_class return only actions which are kind of `filter_class`
    # @return [Array<Action>] of directly planned actions by this action,
    # returned actions are in Present phase
    def planned_actions(filter = Action)
      phase! Present
      plan_step.
          planned_steps(execution_plan).
          map { |s| s.action(execution_plan) }.
          select { |a| a.is_a?(filter) }
    end

    # @param [Class] filter_class return only actions which are kind of `filter_class`
    # @return [Array<Action>] of all (including indirectly) planned actions by this action,
    # returned actions are in Present phase
    def all_planned_actions(filter_class = Action)
      phase! Present
      mine = planned_actions
      (mine + mine.reduce([]) { |arr, action| arr + action.all_planned_actions }).
          select { |a| a.is_a?(filter_class) }
    end

    def run_step
      phase! Present
      execution_plan.steps.fetch(run_step_id) if run_step_id
    end

    def finalize_step
      phase! Present
      execution_plan.steps.fetch(finalize_step_id) if finalize_step_id
    end

    def steps
      [plan_step, run_step, finalize_step]
    end

    def to_hash
      recursive_to_hash(
          { class:                     self.class.name,
            execution_plan_id:         execution_plan_id,
            id:                        id,
            plan_step_id:              plan_step_id,
            run_step_id:               run_step_id,
            finalize_step_id:          finalize_step_id,
            caller_execution_plan_id:  caller_execution_plan_id,
            caller_action_id:          caller_action_id,
            input:                     input },
          if phase? Run, Finalize, Present
            { output: output }
          end)
    end

    def state
      raise "state data not available" if @step.nil?
      @step.state
    end

    # @override to define more descriptive state information for the
    # action: used in Dynflow console
    def humanized_state
      state.to_s
    end

    def error
      raise "error data not available" if @step.nil?
      @step.error
    end

    def execute(*args)
      phase! Executable
      self.send phase.execute_method_name, *args
    end

    # @api private
    # @return [Array<Fixnum>] - ids of steps referenced from action
    def required_step_ids(input = self.input)
      results   = []
      recursion =-> value do
        case value
        when Hash
          value.values.each { |v| recursion.(v) }
        when Array
          value.each { |v| recursion.(v) }
        when ExecutionPlan::OutputReference
          results << value.step_id
        else
          # no reference hidden in this arg
        end
        results
      end
      recursion.(input)
    end

    def execute_delay(delay_options, *args)
      with_error_handling(true) do
        world.middleware.execute(:delay, self, delay_options, *args) do |*new_args|
          @serializer = delay(*new_args).tap do |serializer|
            serializer.perform_serialization!
          end
        end
      end
    end

    def serializer
      raise "The action must be delayed in order to access the serializer" if @serializer.nil?
      @serializer
    end

    protected

    def state=(state)
      phase! Executable
      @world.logger.debug format('%13s %s:%2d %9s >> %9s in phase %8s %s',
                                 'Step', execution_plan_id, @step.id,
                                 self.state, state,
                                 phase.to_s_humanized, self.class)
      @step.state = state
    end

    def save_state
      phase! Executable
      @step.save
    end

    def delay(delay_options, *args)
      Serializers::Noop.new(args)
    end

    # @override to implement the action's *Plan phase* behaviour.
    # By default it plans itself and expects input-hash.
    # Use #plan_self and #plan_action methods to plan actions.
    # It can use DB in this phase.
    def plan(*args)
      if from_subscription?
        # if the action is triggered by subscription, by default use the
        # input of parent action.
        # should be replaced by referencing the input from input format
        plan_self(input.merge(trigger.input))
      else
        # in this case, the action was triggered by plan_action. Use
        # the argument specified there.
        plan_self(*args)
      end
      self
    end

    # Add this method to implement the action's *Run phase* behaviour.
    # It should not use DB in this phase.
    def run(event = nil)
      # just a rdoc placeholder
    end
    remove_method :run

    # Add this method to implement the action's *Finalize phase* behaviour.
    # It can use DB in this phase.
    def finalize
      # just a rdoc placeholder
    end
    remove_method :finalize

    def run_accepts_events?
      method(:run).arity != 0
    end

    def self.new_from_hash(hash, world)
      new(hash, world)
    end

    private

    # DSL for plan phase

    def concurrence(&block)
      phase! Plan
      @execution_plan.switch_flow(Flows::Concurrence.new([]), &block)
    end

    def sequence(&block)
      phase! Plan
      @execution_plan.switch_flow(Flows::Sequence.new([]), &block)
    end

    def plan_self(input = {})
      phase! Plan
      self.input.update input

      if self.respond_to?(:run)
        run_step          = @execution_plan.add_run_step(self)
        @run_step_id      = run_step.id
        @output_reference = OutputReference.new(@execution_plan.id, run_step.id, id)
      end

      if self.respond_to?(:finalize)
        finalize_step     = @execution_plan.add_finalize_step(self)
        @finalize_step_id = finalize_step.id
      end

      return self # to stay consistent with plan_action
    end

    def plan_action(action_class, *args)
      phase! Plan
      @execution_plan.add_plan_step(action_class, self).execute(@execution_plan, self, false, *args)
    end

    # DSL for run phase

    def suspended_action
      phase! Run
      @suspended_action ||= Action::Suspended.new(self)
    end

    def suspend(&block)
      phase! Run
      block.call suspended_action if block
      throw SUSPEND, SUSPEND
    end

    # DSL to terminate action execution and set it to error
    def error!(error)
      phase! Executable
      set_error(error)
      throw ERROR
    end

    def with_error_handling(propagate_error = nil, &block)
      raise "wrong state #{self.state}" unless [:scheduling, :skipping, :running].include?(self.state)

      begin
        catch(ERROR) { block.call }
      rescue Exception => error
        set_error(error)
        # reraise low-level exceptions
        raise error unless Type? error, StandardError, ScriptError
      end

      case self.state
      when :scheduling
        self.state = :pending
      when :running
        self.state = :success
      when :skipping
        self.state = :skipped
      when :suspended, :error
      else
        raise "wrong state #{self.state}"
      end

      if propagate_error && self.state == :error
        raise(@step.error.exception)
      end
    end

    def set_error(error)
      phase! Executable
      Type! error, Exception, String
      action_logger.error error
      self.state  = :error
      @step.error = ExecutionPlan::Steps::Error.new(error)
    end

    def execute_plan(*args)
      phase! Plan
      self.state = :running
      save_state

      # when the error occurred inside the planning, catch that
      # before getting out of the planning phase
      with_error_handling(!root_action?) do
        concurrence do
          world.middleware.execute(:plan, self, *args) do |*new_args|
            plan(*new_args)
          end
        end

        subscribed_actions = world.subscribed_actions(self.class)
        if subscribed_actions.any?
          # we encapsulate the flow for this action into a concurrence and
          # add the subscribed flows to it as well.
          trigger_flow = @execution_plan.current_run_flow.sub_flows.pop
          @execution_plan.switch_flow(Flows::Concurrence.new([trigger_flow].compact)) do
            subscribed_actions.each do |action_class|
              new_plan_step = @execution_plan.add_plan_step(action_class, self)
              new_plan_step.execute(@execution_plan, self, true, *args)
            end
          end
        end

        check_serializable :input
      end
    end

    def execute_run(event)
      phase! Run
      @world.logger.debug format('%13s %s:%2d got event %s',
                                 'Step', execution_plan_id, @step.id, event) if event
      @input = OutputReference.dereference @input, world.persistence

      case
      when state == :running
        raise NotImplementedError, 'recovery after restart is not implemented'

      when [:pending, :error, :skipping, :suspended].include?(state)
        if event && state != :suspended
          raise 'event can be processed only when in suspended state'
        end

        self.state = :running unless self.state == :skipping
        save_state
        with_error_handling do
          event = Skip if state == :skipping

          # we run the Skip event only when the run accepts events
          if event != Skip || run_accepts_events?
            result = catch(SUSPEND) do
              world.middleware.execute(:run, self, *[event].compact) do |*args|
                run(*args)
              end
            end

            self.state = :suspended if result == SUSPEND
          end

          check_serializable :output
        end

      else
        raise "wrong state #{state} when event:#{event}"
      end
    end

    def execute_finalize
      phase! Finalize
      @input     = OutputReference.dereference @input, world.persistence
      self.state = :running
      save_state
      with_error_handling do
        world.middleware.execute(:finalize, self) do
          finalize
        end
      end
    end

    def check_serializable(what)
      Match! what, :input, :output
      value = send what
      recursive_to_hash value # it raises when not serializable
    rescue => e
      value.replace not_serializable: true
      raise e
    end

    def root_action?
      @trigger.nil?
    end
  end
end
