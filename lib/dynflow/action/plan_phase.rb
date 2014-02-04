module Dynflow
  module Action::PlanPhase
    attr_reader :execution_plan, :trigger

    def self.included(base)
      base.attr_indifferent_access_hash :input
    end

    def initialize(attributes, execution_plan, trigger)
      super attributes, execution_plan.world
      plan_step_id || raise(ArgumentError, 'missing plan_step_id')

      self.input      = attributes[:input] || {}
      @execution_plan = Type! execution_plan, ExecutionPlan
      @plan_step_id   = plan_step_id
      @trigger        = Type! trigger, Action, NilClass
    end

    def execute(*args)
      self.state = :running
      save_state
      with_error_handling do
        concurrence do
          world.middleware.execute(:plan, self, *args) do |*new_args|
            plan(*new_args)
          end
        end

        subscribed_actions = world.subscribed_actions(self.action_class)
        if subscribed_actions.any?
          # we encapsulate the flow for this action into a concurrence and
          # add the subscribed flows to it as well.
          trigger_flow = execution_plan.current_run_flow.sub_flows.pop
          execution_plan.switch_flow(Flows::Concurrence.new([trigger_flow].compact)) do
            subscribed_actions.each do |action_class|
              new_plan_step = execution_plan.add_plan_step(action_class, self)
              new_plan_step.execute(execution_plan, self, *args)
            end
          end
        end
      end
    end

    def to_hash
      super.merge recursive_to_hash(input: input)
    end

    # DSL for plan method

    def concurrence(&block)
      execution_plan.switch_flow(Flows::Concurrence.new([]), &block)
    end

    def sequence(&block)
      execution_plan.switch_flow(Flows::Sequence.new([]), &block)
    end

    def plan_self(input)
      @input = input.with_indifferent_access
      if self.respond_to?(:run)
        run_step          = execution_plan.add_run_step(self)
        @run_step_id      = run_step.id
        @output_reference = ExecutionPlan::OutputReference.new(run_step.id, id)
      end

      if self.respond_to?(:finalize)
        finalize_step     = execution_plan.add_finalize_step(self)
        @finalize_step_id = finalize_step.id
      end

      return self # to stay consistent with plan_action
    end

    def plan_action(action_class, *args)
      execution_plan.add_plan_step(action_class, self).execute(execution_plan, nil, *args)
    end

    def output
      unless @output_reference
        raise 'plan_self has to be invoked before being able to reference the output'
      end

      return @output_reference
    end

  end
end
