module Dynflow
  module Testing
    module Factories
      include Algebrick::TypeCheck

      # @return [Action::PlanPhase]
      def create_action(action_class, trigger = nil)
        execution_plan = DummyExecutionPlan.new
        step           = DummyStep.new
        action_class.plan_phase.new(
            { step:              DummyStep.new,
              execution_plan_id: execution_plan.id,
              id:                Testing.get_id,
              plan_step_id:      step.id },
            execution_plan, trigger)
      end

      # @return [Action::PlanPhase]
      def plan_action(plan_action, *args, &block)
        Type! plan_action, Dynflow::Action::PlanPhase

        plan_action.execute *args, &block
        raise plan_action.error if plan_action.error
        plan_action
      end

      def create_and_plan_action(action_class, *args, &block)
        plan_action create_action(action_class), *args, &block
      end

      # @return [Action::RunPhase]
      def run_action(plan_action, event = nil)
        Type! plan_action, Dynflow::Action::PlanPhase, Dynflow::Action::RunPhase
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

      # @return [Action::FinalizePhase]
      def finalize_action(run_action)
        Type! run_action, Dynflow::Action::RunPhase
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
