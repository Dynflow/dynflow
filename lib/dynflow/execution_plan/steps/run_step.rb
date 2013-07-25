module Dynflow
  module ExecutionPlan::Steps
    class RunStep < Abstract

      def action
        action_hash = persistence_adapter.load_action(execution_plan.id, action_id)
        # TODO: dereference if possible
        Action.run_phase.new_from_hash(action_hash, self.state, self.id, execution_plan.world)
      end

      def execute
      end
    end
  end
end
