require 'active_support/inflector'

module Dynflow
  class Action < Serializable

    OutputReference = ExecutionPlan::OutputReference

    include Algebrick::TypeCheck
    include Algebrick::Matching

    require 'dynflow/action/format'
    extend Format

    require 'dynflow/action/progress'
    include Progress

    require 'dynflow/action/suspended'
    require 'dynflow/action/missing'

    require 'dynflow/action/polling'
    require 'dynflow/action/cancellable_polling'

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
                :plan_step_id, :run_step_id, :finalize_step_id

    def initialize(attributes, world)
      Type! attributes, Hash

      @phase             = Type! attributes.fetch(:phase), Phase
      @world             = Type! world, World
      @step              = Type!(attributes.fetch(:step),
                                 ExecutionPlan::Steps::Abstract) if phase? Executable
      @execution_plan_id = Type! attributes.fetch(:execution_plan_id), String
      @id                = Type! attributes.fetch(:id), Integer
      @plan_step_id      = Type! attributes.fetch(:plan_step_id), Integer
      @run_step_id       = Type! attributes.fetch(:run_step_id), Integer, NilClass
      @finalize_step_id  = Type! attributes.fetch(:finalize_step_id), Integer, NilClass

      @execution_plan    = Type!(attributes.fetch(:execution_plan),
                                 ExecutionPlan) if phase? Plan, Present
      @trigger           = Type! attributes.fetch(:trigger), Action, NilClass if phase? Plan

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
      @input = hash.with_indifferent_access
    end

    def output=(hash)
      Type! hash, Hash
      phase! Run
      @output = hash.with_indifferent_access
    end

    def output
      if phase? Plan
        @output_reference or
            raise 'plan_self has to be invoked before being able to reference the output'
      else
        @output
      end
    end

    def trigger
      phase! Plan
      @trigger
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
          map { |s| s.action execution_plan }.
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
          { class:             self.class.name,
            execution_plan_id: execution_plan_id,
            id:                id,
            plan_step_id:      plan_step_id,
            run_step_id:       run_step_id,
            finalize_step_id:  finalize_step_id,
            input:             input },
          if phase? Run, Finalize, Present
            { output: output }
          end)
    end

    def state
      phase! Executable
      @step.state
    end

    def error
      phase! Executable
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

    # @override to implement the action's *Plan phase* behaviour.
    # By default it plans itself and expects input-hash.
    # Use #plan_self and #plan_action methods to plan actions.
    # It can use DB in this phase.
    def plan(*args)
      if trigger
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
      @execution_plan.add_plan_step(action_class, self).execute(@execution_plan, nil, *args)
    end

    # DSL for run phase

    def suspend(&block)
      phase! Run
      block.call Action::Suspended.new self if block
      throw SUSPEND, SUSPEND
    end

    # DSL to terminate action execution and set it to error
    def error!(error)
      phase! Executable
      set_error(error)
      throw ERROR
    end

    def with_error_handling(&block)
      raise "wrong state #{self.state}" unless self.state == :running

      begin
        catch(ERROR) { block.call }
      rescue Exception => error
        set_error(error)
        # reraise low-level exceptions
        raise error unless Type? error, StandardError, ScriptError
      end

      case self.state
      when :running
        self.state = :success
      when :suspended, :error
      else
        raise "wrong state #{self.state}"
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
      with_error_handling do
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
              new_plan_step.execute(@execution_plan, self, *args)
            end
          end
        end
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

      when [:pending, :error, :suspended].include?(state)
        if [:pending, :error].include?(state) && event
          raise 'event can be processed only when in suspended state'
        end

        self.state = :running
        save_state
        with_error_handling do
          result = catch(SUSPEND) do
            world.middleware.execute(:run, self, *[event].compact) { |*args| run(*args) }
          end
          if result == SUSPEND
            self.state = :suspended
          end
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
  end
end
