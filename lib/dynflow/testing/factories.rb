module Dynflow
  module Testing
    module Factories
      def plan_action_with_trigger(action_class, trigger, *args, &block)
        execution_plan = DummyExecutionPlan.new
        step           = DummyStep.new
        action         = action_class.plan_phase.new(
            { step:              DummyStep.new,
              execution_plan_id: execution_plan.id,
              id:                Testing.get_id,
              plan_step_id:      step.id },
            execution_plan, trigger)

        action.execute *args, &block
        raise action.error if action.error

        action
      end

      # @return [Action::PlanPhase]
      def plan_action(action_class, *args, &block)
        plan_action_with_trigger action_class, nil, *args, &block
      end

      # @return [Action::FinalizePhase]
      def run_action(plan_action, event = nil)
        step       = DummyStep.new
        run_action = if Dynflow::Action::PlanPhase === plan_action
                       plan_action.action_class.run_phase.new(
                           { step:              step,
                             execution_plan_id: plan_action.execution_plan_id,
                             id:                plan_action.id,
                             plan_step_id:      plan_action.plan_step_id,
                             run_step_id:       step.id,
                             input:             plan_action.input },
                           plan_action.world)

                     else
                       plan_action
                     end

        run_action.world.action ||= run_action
        run_action.world.clock.clear
        run_action.execute event
        raise run_action.error if run_action.error
        run_action
      end

      # @return [Action]
      def finalize_action(run_action)
        step            = DummyStep.new
        finalize_action = run_action.action_class.finalize_phase.new(
            { step:              step,
              execution_plan_id: run_action.execution_plan_id,
              id:                run_action.id,
              plan_step_id:      run_action.plan_step_id,
              run_step_id:       run_action.run_step_id,
              finalize_step_id:  step.id,
              input:             run_action.input },
            run_action.world)

        finalize_action.execute
        finalize_action
      end

      def clock_progress action
        action.world.clock.progress
      end
    end
  end
end
