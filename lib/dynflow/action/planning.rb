module Dynflow
  module Action::Planning
    attr_reader :execution_plan, :trigger, :input, :plan_step

    def initialize(world, status, id, execution_plan, plan_step, trigger)
      super world, status, id
      @input          = {}
      @execution_plan = is_kind_of! execution_plan, ExecutionPlan
      @plan_step       = plan_step
      @trigger        = is_kind_of! trigger, Action, NilClass
    end

    def execute(*args)
      execution_plan.switch_flow(Flows::Concurrence.new([])) do
        plan(*args)
      end

      subscribed_actions = world.subscribed_actions(self.action_class)
      if subscribed_actions.any?
        # we ancapsulate the flow for this action into a concurrence and
        # add the subscribed flows to it as well.
        trigger_flow = execution_plan.current_run_flow.sub_flows.pop
        execution_plan.switch_flow(Flows::Concurrence.new([trigger_flow])) do
          subscribed_actions.each do |action_class|
            execution_plan.add_plan_step(action_class, self).execute(self, *args)
          end
        end
      end
    end

    def to_hash
      super.merge input: input
    end

    # DSL for plan method

    def concurrence(&block)
      execution_plan.switch_flow(Flows::Concurrence.new([]), &block)
    end

    def sequence(&block)
      execution_plan.switch_flow(Flows::Sequence.new([]), &block)
    end

    def plan_self(input)
      @input = input
      @run_step = execution_plan.add_run_step self if self.respond_to? :run
      execution_plan.add_finalize_step self if self.respond_to? :finalize
      return self # to stay consistent with plan_action
    end

    def plan_action(action_class, *args)
      execution_plan.add_plan_step(action_class, self).execute(nil, *args)
    end

    def output
      return @output_reference if @output_reference

      unless @run_step
        raise 'plan_self has to be invoked before being able to reference the output'
      end
      @output_reference = ExecutionPlan::Steps::OutputReference.new(@run_step.id)
    end

  end
end
