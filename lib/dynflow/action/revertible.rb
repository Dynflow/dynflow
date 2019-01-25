module Dynflow
  class Action
    module Revertible

      def rescue_strategy_for_self
        Rescue::Revert
      end

      def revert_run
        # just a rdoc placeholder
      end
      remove_method :revert_run

      def revert_plan
        # just a rdoc placeholder
      end
      remove_method :revert_plan

      def original_input
        input.fetch(:input, {})
      end

      def original_output
        input.fetch(:output, {})
      end

      # General approach
      # Take all the child actions of the action we're reverting, reverse their order
      # plan those which went through planning (eg. not pending plan step state)
      # plan self if the action attempted to run (eg. not pending run step state)
      def revert(parent_action)
        sequence do
          parent_action.planned_actions.reverse.each do |action|
            revert_action(action) if action.plan_step.state != :pending && action.run_step.state != :pending
          end
          revert_self(parent_action)
        end
      end

    end
  end
end
