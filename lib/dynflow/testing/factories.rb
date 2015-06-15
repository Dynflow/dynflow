module Dynflow
  module Testing
    module Factories
      include Algebrick::TypeCheck

      # @return [Action::PlanPhase]
      def create_action(action_class, trigger = nil)
        execution_plan = DummyExecutionPlan.new
        step           = DummyStep.new
        action_class.new(
            { step:              DummyStep.new,
              execution_plan_id: execution_plan.id,
              id:                Testing.get_id,
              phase:             Action::Plan,
              plan_step_id:      step.id,
              run_step_id:       nil,
              finalize_step_id:  nil },
            execution_plan.world).tap do |action|
          action.set_plan_context(execution_plan, trigger, false)
        end
      end

      def create_action_presentation(action_class)
        execution_plan = DummyExecutionPlan.new
        action_class.new(
            { execution_plan:    execution_plan,
              execution_plan_id: execution_plan.id,
              id:                Testing.get_id,
              phase:             Action::Present,
              plan_step_id:      1,
              run_step_id:       nil,
              finalize_step_id:  nil,
              input:             nil },
            execution_plan.world)
      end

      # @return [Action::PlanPhase]
      def plan_action(plan_action, *args, &block)
        Match! plan_action.phase, Action::Plan

        plan_action.execute *args, &block
        raise plan_action.error if plan_action.error
        plan_action
      end

      def create_and_plan_action(action_class, *args, &block)
        plan_action create_action(action_class), *args, &block
      end

      # @return [Action::RunPhase]
      def run_action(plan_action, event = nil, &stubbing)
        Match! plan_action.phase, Action::Plan, Action::Run
        step       = DummyStep.new
        run_action = if plan_action.phase == Action::Plan
                       plan_action.class.new(
                           { step:              step,
                             execution_plan_id: plan_action.execution_plan_id,
                             id:                plan_action.id,
                             plan_step_id:      plan_action.plan_step_id,
                             run_step_id:       step.id,
                             finalize_step_id:  nil,
                             phase:             Action::Run,
                             input:             plan_action.input },
                           plan_action.world)

                     else
                       plan_action
                     end

        run_action.world.action ||= run_action
        run_action.world.clock.clear
        stubbing.call run_action if stubbing
        run_action.execute event
        raise run_action.error if run_action.error
        run_action
      end

      # @return [Action::FinalizePhase]
      def finalize_action(run_action, &stubbing)
        Match! run_action.phase, Action::Plan, Action::Run
        step            = DummyStep.new
        finalize_action = run_action.class.new(
            { step:              step,
              execution_plan_id: run_action.execution_plan_id,
              id:                run_action.id,
              plan_step_id:      run_action.plan_step_id,
              run_step_id:       run_action.run_step_id,
              finalize_step_id:  step.id,
              phase:             Action::Finalize,
              input:             run_action.input },
            run_action.world)

        stubbing.call finalize_action if stubbing
        finalize_action.execute
        finalize_action
      end

      def progress_action_time action
        Match! action.phase, Action::Run
        if action.world.clock.progress
          return action.world.executor.progress
        end
      end
    end
  end
end
