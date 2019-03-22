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

      module FlagHook
        def raise_flag(_execution_plan)
          Flag.raise!
        end

        def controlled_failure(_execution_plan)
          Flag.raise!
          raise "A controlled failure"
        end
      end

      class ActionWithHooks < ::Dynflow::Action
        include FlagHook

        execution_plan_hooks.use :raise_flag, :on => :success
      end

      class ActionOnStop < ::Dynflow::Action
        include FlagHook

        execution_plan_hooks.use :controlled_failure, :on => :stopped
      end

      class ActionOnFailure < ::Dynflow::Action
        include FlagHook

        execution_plan_hooks.use :raise_flag, :on => :failure
      end

      class ActionOnPause < ::Dynflow::Action
        include FlagHook

        def run
          error!("pause")
        end

        def rescue_strategy
          Dynflow::Action::Rescue::Pause
        end

        execution_plan_hooks.use :raise_flag, :on => :paused
      end

      class Inherited < ActionWithHooks; end
      class Overriden < ActionWithHooks
        execution_plan_hooks.do_not_use :raise_flag
      end

      before { Flag.lower! }
      after { world.persistence.delete_delayed_plans({}) }

      it 'runs the on_success hook' do
        refute Flag.raised?
        plan = world.trigger(ActionWithHooks)
        plan.finished.wait!
        assert Flag.raised?
      end

      it 'runs the on_pause hook' do
        refute Flag.raised?
        plan = world.trigger(ActionOnPause)
        plan.finished.wait!
        assert Flag.raised?
      end

      describe 'with auto_rescue' do
        let(:world) do
          WorldFactory.create_world do |config|
            config.auto_rescue = true
          end
        end

        it 'runs the on_pause hook' do
          refute Flag.raised?
          plan = world.trigger(ActionOnPause)
          plan.finished.wait!
          assert Flag.raised?
        end
      end

      it 'runs the on_failure hook on cancel' do
        refute Flag.raised?
        @start_at = Time.now.utc + 180
        delay = world.delay(ActionOnFailure, { :start_at => @start_at })
        delayed_plan = world.persistence.load_delayed_plan(delay.execution_plan_id)
        delayed_plan.execution_plan.cancel.each(&:wait)
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
