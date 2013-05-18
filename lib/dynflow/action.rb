module Dynflow
  class Action

    class Dependency < Apipie::Params::Descriptor::Base

      attr_reader :action_class, :attr

      extend Forwardable

      def_delegators :@descriptor, :description, :invalid_param_error, :json_schema, :param, :params

      def initialize(action_class, attr)
        @descriptor = case attr
                      when :input then action_class.input_format
                      when :output then action_class.output_format
                      else
                        raise ArgumentError, 'attr can be either :input of :output'
                      end

        @action_class = action_class
        @attr = attr
      end
    end

    # only for the planning phase: flag indicating that the action
    # was triggered from subscription. If so, the implicit plan
    # method uses the input of the parent action. Otherwise, the
    # argument the plan_action is used as default.
    attr_accessor :execution_plan, :from_subscription, :input, :output

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
      # for preparation phase
      @execution_plan = ExecutionPlan.new

      @input = input
      @output = output || {}
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
      action = self.new({})
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

      action.execution_plan
    end

    # for subscribed actions: by default take the input of the
    # subscribed action
    def plan(*args)
      if from_subscription
        # if the action is triggered by subscription, by default use the
        # input of parent action
        plan_self(self.input)
      else
        # in this case, the action was triggered by plan_action. Use
        # the argument specified there.
        plan_self(args.first)
      end
    end

    def plan_self(input)
      self.input = input
      @execution_plan << self
    end

    def plan_action(action_class, *args)
      sub_action_plan = action_class.plan(*args) do |action|
        action.input = self.input
      end
      @execution_plan.concat(sub_action_plan)
    end

    def add_subscriptions(*plan_args)
      @execution_plan.concat(Dispatcher.execution_plan_for(self, *plan_args))
    end

    def execution_plan
      @execution_plan
    end

    def validate!
      self.clss.output_format.validate!(output)
    end

  end
end
