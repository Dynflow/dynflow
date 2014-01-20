module Dynflow
  module Testing
    module Assertions
      # assert that +assert_actioned_plan+ was planned by +action+ with arguments +plan_input+
      # alternatively plan-input can be asserted with +block+
      def assert_action_planed_with(action, planned_action_class, *plan_input, &block)
        found_classes = assert_action_planed(action, planned_action_class)
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

      # assert that +assert_actioned_plan+ was planned by +action+
      def assert_action_planed(action, planned_action_class)
        Type! action, Dynflow::Action::PlanPhase
        Match! action.state, :success
        found = action.execution_plan.planned_plan_steps.
            select { |a| a.is_a?(planned_action_class) }

        assert(!found.empty?, "Action #{planned_action_class} was not planned")
        found
      end

      # assert that +action+ has run-phase planned
      def assert_run_phase(action, input = nil, &block)
        Type! action, Dynflow::Action::PlanPhase
        Match! action.state, :success
        action.execution_plan.planned_run_steps.must_include action
        action.input.must_equal input.stringify_keys if input
        block.call input if block
      end

      # refute that +action+ has run-phase planned
      def refute_run_phase(action)
        Type! action, Dynflow::Action::PlanPhase
        Match! action.state, :success
        action.execution_plan.planned_run_steps.wont_include action
      end

      # assert that +action+ has finalize-phase planned
      def assert_finalize_phase(action)
        Type! action, Dynflow::Action::PlanPhase
        Match! action.state, :success
        action.execution_plan.planned_finalize_steps.must_include action
      end

      # refute that +action+ has finalize-phase planned
      def refute_finalize_phase(action)
        Type! action, Dynflow::Action::PlanPhase
        Match! action.state, :success
        action.execution_plan.planned_finalize_steps.wont_include action
      end

    end
  end
end
