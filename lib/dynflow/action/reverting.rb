module Dynflow
  class Action
    class Reverting < ::Dynflow::Action

      # General approach
      # Take all the child actions of the action were reverting, reverse their order
      # plan those which went through planning (eg. not pending plan step state)
      # plan self if the action attempted to run (eg. not pending run step state)
      def plan(parent_action)
        # TODO: Reuse run_flow of parent_action.execution_plan, sequence is safe but not ideal performance-wise
        sequence do
          parent_action.planned_actions.reverse.each do |action|
            plan_action(action.class.revert_action_class, action) if action.plan_step.state != :pending
          end
          plan_self(parent_action) if parent_action.run_step && parent_action.run_step.state != :pending
        end
      end

      private

      def entry_action?
        id == 1
      end

      def original_input
        input[:input]
      end

      def original_output
        input[:output]
      end
    end
  end
end
