module Dynflow
  module ExecutionPlan::Steps
    module Revert

      def original_step(action, kind)
        world.persistence.load_step(action.input['execution_plan_id'],
                                    action.input[kind + '_step_id'],
                                    world)
      end

      def reset_original_step!(action, kind)
        return if action.input[kind + '_step_id'].nil?
        step = original_step(action, kind)
        step.set_state :reverted, true
        step.save
      end

      def original_execution_plan(action)
        @original_execution_plan ||= world.persistence.load_execution_plan(action.input['execution_plan_id'])
      end

      def entry_action?(action)
        action.plan_step_id == 1
      end
    end
  end
end
