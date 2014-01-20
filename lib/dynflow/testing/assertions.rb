module Dynflow
  module Testing
   module Assertions
      def assert_action_plan_with(action, planned_action_class, *plan_input, &block)
        found_classes = assert_action_plan(action, planned_action_class)
        found         = found_classes.select do |a|
          if plan_input.empty?
            block.call a.plan_input
          else
            a.plan_input == plan_input
          end
        end

        assert(!found.empty?,
               "Action #{planned_action_class} with plan_input #{plan_input} was not planned, there were only #{found_classes.map(&:plan_input)}")
        found
      end

      def assert_action_plan(action, planned_action_class)
        found = action.execution_plan.planned_plan_steps.
            select { |a| a.is_a?(planned_action_class) }

        assert(!found.empty?, "Action #{planned_action_class} was not planned")
        found
      end

      def assert_action_run_planned(action, run_action = action)
        action.execution_plan.planned_run_steps.must_include action
      end

      def refute_action_run_planned(action, run_action = action)
        action.execution_plan.planned_run_steps.wont_include action
      end

      def assert_action_finalize_planned(action, finalize_action = action)
        action.execution_plan.planned_finalize_steps.must_include action
      end

      def refute_action_finalize_planned(action, finalize_action = action)
        action.execution_plan.planned_finalize_steps.wont_include action
      end

    end
  end
end
