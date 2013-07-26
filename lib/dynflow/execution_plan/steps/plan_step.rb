module Dynflow
  module ExecutionPlan::Steps
    class PlanStep < Abstract
      attr_reader :children

      def initialize(execution_plan, id, state, action_class, action_id)
        super execution_plan, id, state, action_class, action_id
        @children = []
      end

      # @return [Action]
      def execute(trigger, *args)
        attributes = { id: action_id, state: :pending, plan_step_id: self.id }
        action     = action_class.plan_phase.new(attributes, execution_plan, trigger)

        action.execute(*args)
        self.state = action.state

        persistence_adapter.save_action(execution_plan.id, action_id, action.to_hash)
        return action
      end
    end
  end
end
