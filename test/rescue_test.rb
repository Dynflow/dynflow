# frozen_string_literal: true

require_relative 'test_helper'

module Dynflow
  module RescueTest
    describe 'on error' do

      Example = Support::RescueExample

      let(:world) { WorldFactory.create_world }

      def execute(*args)
        plan = world.plan(*args)
        raise plan.errors.first if plan.error?
        world.execute(plan.id).value
      end

      let :rescued_plan do
        world.persistence.load_execution_plan(execution_plan.id)
      end

      describe 'no auto rescue' do
        describe 'of simple skippable action in run phase' do

          let :execution_plan do
            execute(Example::ActionWithSkip, 1, :error_on_run)
          end

          it 'suggests skipping the action' do
            _(execution_plan.rescue_strategy).must_equal Action::Rescue::Skip
          end

          it "doesn't rescue" do
            _(rescued_plan.state).must_equal :paused
          end
        end

        describe 'of simple skippable action in finalize phase' do

          let :execution_plan do
            execute(Example::ActionWithSkip, 1, :error_on_finalize)
          end

          it 'suggests skipping the action' do
            _(execution_plan.rescue_strategy).must_equal Action::Rescue::Skip
          end

          it "doesn't rescue" do
            _(rescued_plan.state).must_equal :paused
          end
        end

        describe 'of complex action with skips in run phase' do

          let :execution_plan do
            execute(Example::ComplexActionWithSkip, :error_on_run)
          end

          it 'suggests skipping the action' do
            _(execution_plan.rescue_strategy).must_equal Action::Rescue::Skip
          end

          it "doesn't rescue" do
            _(rescued_plan.state).must_equal :paused
          end
        end

        describe 'of complex action with skips in finalize phase' do

          let :execution_plan do
            execute(Example::ComplexActionWithSkip, :error_on_finalize)
          end

          it 'suggests skipping the action' do
            _(execution_plan.rescue_strategy).must_equal Action::Rescue::Skip
          end

          it "doesn't rescue" do
            _(rescued_plan.state).must_equal :paused
          end
        end

        describe 'of complex action without skips' do

          let :execution_plan do
            execute(Example::ComplexActionWithoutSkip, :error_on_run)
          end

          it 'suggests pausing the plan' do
            _(execution_plan.rescue_strategy).must_equal Action::Rescue::Pause
          end

          it "doesn't rescue" do
            _(rescued_plan.state).must_equal :paused
          end
        end

        describe 'of complex action with fail' do

          let :execution_plan do
            execute(Example::ComplexActionWithFail, :error_on_run)
          end

          it 'suggests failing the plan' do
            _(execution_plan.rescue_strategy).must_equal Action::Rescue::Fail
          end

          it "doesn't rescue" do
            _(rescued_plan.state).must_equal :paused
          end
        end
      end

      describe 'auto rescue' do

        let(:world) do
          WorldFactory.create_world do |config|
            config.auto_rescue = true
          end
        end

        describe 'of simple skippable action in run phase' do
          let :execution_plan do
            execute(Example::ActionWithSkip, 1, :error_on_run)
          end

          it 'skips the action and continues' do
            _(rescued_plan.state).must_equal :stopped
            _(rescued_plan.result).must_equal :warning
            _(rescued_plan.entry_action.output[:message]).
              must_equal "skipped because some error as you wish"
          end
        end

        describe 'of simple skippable action in finalize phase' do
          let :execution_plan do
            execute(Example::ActionWithSkip, 1, :error_on_finalize)
          end

          it 'skips the action and continues' do
            _(rescued_plan.state).must_equal :stopped
            _(rescued_plan.result).must_equal :warning
            _(rescued_plan.entry_action.output[:message]).must_equal "Been here"
          end
        end

        describe 'of plan with skips' do
          let :execution_plan do
            execute(Example::ComplexActionWithSkip, :error_on_run)
          end

          it 'skips the action and continues automatically' do
            _(execution_plan.state).must_equal :stopped
            _(execution_plan.result).must_equal :warning
            skipped_action = rescued_plan.actions.find do |action|
              action.run_step && action.run_step.state == :skipped
            end
            _(skipped_action.output[:message]).must_equal "skipped because some error as you wish"
          end
        end

        describe 'of complex action with skips in finalize phase' do
          let :execution_plan do
            execute(Example::ComplexActionWithSkip, :error_on_finalize)
          end

          it 'skips the action and continues' do
            _(rescued_plan.state).must_equal :stopped
            _(rescued_plan.result).must_equal :warning
            skipped_action = rescued_plan.actions.find do |action|
              action.steps.find { |step| step && step.state == :skipped }
            end
            _(skipped_action.output[:message]).must_equal "Been here"
          end
        end

        describe 'of plan faild on auto-rescue' do
          let :execution_plan do
            execute(Example::ActionWithSkip, 1, :error_on_skip)
          end

          it 'tried to rescue only once' do
            _(execution_plan.state).must_equal :paused
            _(execution_plan.result).must_equal :error
          end
        end

        describe 'of plan without skips' do
          let :execution_plan do
            execute(Example::ComplexActionWithoutSkip, :error_on_run)
          end

          it 'skips the action and continues automatically' do
            _(execution_plan.state).must_equal :paused
            _(execution_plan.result).must_equal :error
            expected_history = [['start execution', world.id],
                                ['pause execution', world.id]]
            _(execution_plan.execution_history.map { |h| [h.name, h.world_id] }).must_equal(expected_history)
          end
        end

        describe 'of plan with fail' do
          let :execution_plan do
            execute(Example::ComplexActionWithFail, :error_on_run)
          end

          it 'fails the execution plan automatically' do
            _(execution_plan.state).must_equal :stopped
            _(execution_plan.result).must_equal :error
            _(execution_plan.steps_in_state(:success).count).must_equal 6
            _(execution_plan.steps_in_state(:pending).count).must_equal 6
            _(execution_plan.steps_in_state(:error).count).must_equal 1
            expected_history = [['start execution', world.id],
                                ['finish execution', world.id]]
            _(execution_plan.execution_history.map { |h| [h.name, h.world_id] }).must_equal(expected_history)
          end
        end

      end
    end
  end
end
