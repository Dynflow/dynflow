module Dynflow
  class Action

    # Used for specifying dependencies in input_format
    class Dependency < Apipie::Params::Descriptor::Base

      attr_reader :action_class, :field

      extend Forwardable

      def_delegators :@descriptor, :description, :invalid_param_error, :json_schema, :param, :params

      def initialize(action_class, field)
        @descriptor = case field
                      when :input then action_class.input_format
                      when :output then action_class.output_format
                      else
                        raise ArgumentError, 'field can be either :input of :output'
                      end

        @action_class = action_class
        @field = field
      end

      def self.build(*args)
        # we don't want this class to be buildable directly from the DSL
      end

    end

    # only for the planning phase: action that caused this action
    # to be triggered. In other words, this action was subscribed to
    # a class of the trigger.
    # If trigger present, the implicit plan
    # method uses the input of the trigger. Otherwise, the
    # argument the plan_action is used as default.
    attr_accessor :trigger

    # for planning phase
    attr_reader :execution_plan

    attr_accessor :input, :output

    def self.inherited(child)
      self.actions << child
    end

    def self.actions
      @actions ||= []
    end

    def self.subscribe
      nil
    end

    def self.require
      nil
    end

    def initialize(input, output = nil)
      @input = input
      @output = output || {}

      # for preparation phase
      if output == :reference
        # needed for steps initialization, quite hackish, fix!
        @output = {}

        @execution_plan = ExecutionPlan.new
        @run_step = Step::Run.new(self)
        @finalize_step = Step::Finalize.new(@run_step)
        @output = Step::Reference.new(@run_step, :output)
      end
    end


    def ==(other)
      [self.class.name, self.input, self.output] ==
        [other.class.name, other.input, other.output]
    end

    def inspect
      "#{self.class.name}: #{input.inspect} ~> #{output.inspect}"
    end

    # the block contains the expression in Apipie::Params::DSL
    # describing the format of message
    def self.input_format(&block)
      if block
        @input_format_block = block
      elsif @input_format_block
        @input_format ||= Apipie::Params::Description.define(&@input_format_block)
      else
        nil
      end
    end

    # the block contains the expression in Apipie::Params::DSL
    # describing the format of message
    def self.output_format(&block)
      if block
        @output_format_block = block
      elsif @output_format_block
        @output_format ||= Apipie::Params::Description.define(&@output_format_block)
      else
        nil
      end
    end

    # use when referencing output from another action's input_format
    def self.input
      Dependency.new(self, :input)
    end

    # use when referencing output from another action's input_format
    def self.output
      Dependency.new(self, :output)
    end

    def self.trigger(*args)
      Dynflow::Bus.trigger(self, *args)
    end

    def self.plan(*args)
      action = self.new({}, :reference)
      yield action if block_given?

      plan_step = Step::Plan.new(action)
      action.execution_plan.plan_steps << plan_step
      plan_step.catch_errors do
        action.plan(*args)
      end

      if action.execution_plan.failed_steps.any?
        action.execution_plan.status = 'error'
      else
        action.add_subscriptions(*args)
      end

      return action
    end

    # for subscribed actions: by default take the input of the
    # subscribed action
    def plan(*args)
      if trigger
        # if the action is triggered by subscription, by default use the
        # input of parent action.
        # should be replaced by referencing the input from input format
        plan_self(trigger.input.dup)
      else
        # in this case, the action was triggered by plan_action. Use
        # the argument specified there.
        plan_self(args.first)
      end
    end

    def plan_self(input)
      self.input = input
      @run_step.input = self.input
      @finalize_step.input = input
      @execution_plan << @run_step if self.respond_to? :run
      @execution_plan << @finalize_step if self.respond_to? :finalize
      return self # to stay consistent with plan_action
    end

    def plan_action(action_class, *args)
      sub_action = action_class.plan(*args) do |action|
        action.input = self.input
      end
      @execution_plan.concat(sub_action.execution_plan)
      return sub_action
    end

    def add_subscriptions(*plan_args)
      @execution_plan.concat(Dispatcher.execution_plan_for(self, *plan_args))
    end

    # If triggered with subscription, check if the trigger output is
    # not reference in input_format. If so, make the reference in the input.
    def add_trigger_reference
      trigger_dependencies = self.class.input_format.params.find_all do |description|
        descriptor = description.descriptor
        descriptor.is_a?(Dependency) && descriptor.action_class == trigger.class
      end.map { |description| [description.name, description.descriptor] }

      trigger_dependencies.each do |name, dependency|
        self.input[name.to_s] = case dependency.field
                                when :input then trigger.input
                                when :output then trigger.output
                                else raise ArgumentError, "Unknown dependency field: #{dependency.field}"
        end
      end
    end

    def validate!
      self.class.output_format.validate!(output)
    end

  end
end
