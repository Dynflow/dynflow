require_relative 'test_helper'

module Dynflow
  class ExecutionPlan
    describe Hooks do
      include PlanAssertions

      let(:world) { WorldFactory.create_world }

      class Flag
        class << self
          def raise!
            @raised = true
          end

          def raised?
            @raised
          end

          def lower!
            @raised = false
          end
        end
      end

      class FlagHook < ::Dynflow::ExecutionPlan::Hooks::Abstract
        def on_success(_execution_plan, _action)
          Flag.raise!
        end

        def on_stop(_execution_plan, _action)
          Flag.raise!
          raise "A controlled failure"
        end
      end

      class ActionWithHooks < ::Dynflow::Action
        execution_plan_hooks.use FlagHook, :on => :success
      end

      class ActionOnStop < ::Dynflow::Action
        execution_plan_hooks.use FlagHook, :on => :stop
      end

      class Inherited < ActionWithHooks; end
      class Overriden < ActionWithHooks
        execution_plan_hooks.do_not_use FlagHook
      end

      before { Flag.lower! }

      it 'runs the on_success hook' do
        refute Flag.raised?
        plan = world.trigger(ActionWithHooks)
        plan.finished.wait!
        assert Flag.raised?
      end

      it 'does not alter the execution plan when exception happens in the hook' do
        refute Flag.raised?
        plan = world.plan(ActionOnStop)
        plan = world.execute(plan.id).wait!.value
        assert Flag.raised?
        plan.result.must_equal :success
      end

      it 'inherits the hooks when subclassing' do
        refute Flag.raised?
        plan = world.trigger(Inherited)
        plan.finished.wait!
        assert Flag.raised?
      end

      it 'can override the hooks from the child' do
        refute Flag.raised?
        plan = world.trigger(Overriden)
        plan.finished.wait!
        refute Flag.raised?
      end
    end
  end
end
