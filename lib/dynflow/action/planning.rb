module Dynflow
  module Action::Planning
    attr_reader :execution_plan, :trigger, :input

    def initialize(world, status, id, execution_plan, trigger)
      super world, status, id
      @input          = {}
      @execution_plan = execution_plan
      @trigger        = trigger
    end

    def execute(*args)
      execution_plan.with_planning_scope do
        plan *args
      end
      world.subscribed_actions(self).each do |action_class|
        execution_plan.add_plan_step(action_class, self).execute(self, *args)
      end
    end

    def to_hash
      super.merge input: input
    end

    # DSL for plan method

    def concurrence(&block)
      execution_plan.switch_scope(Concurrence, &block)
    end

    def sequence(&block)
      execution_plan.switch_scope(Sequence, &block)
    end

    def plan_self(input)
      self.input = input
      execution_plan.add_run_step self if self.respond_to? :run
      execution_plan.add_finalize_step self if self.respond_to? :finalize
      return self # to stay consistent with plan_action
    end

    def plan_action(action_class, *args)
      execution_plan.add_plan_step(action_class, self).execute(nil, *args)
    end
  end
end
