require_relative 'test_helper'

module Dynflow

  CWE = Support::CodeWorkflowExample

  describe Testing do
    include Testing

    describe 'testing' do

      specify '#plan_action' do
        input  = { 'input' => 'input' }
        action = create_and_plan_action Support::DummyExample::WeightedPolling, input

        action.must_be_kind_of Support::DummyExample::WeightedPolling
        action.phase.must_equal Action::Plan
        action.input.must_equal input
        action.execution_plan.must_be_kind_of Testing::DummyExecutionPlan
        action.state.must_equal :success
        assert_run_phase action
        assert_finalize_phase action
        assert_action_planed action, Support::DummyExample::Polling
        refute_action_planed action, CWE::DummyAnotherTrigger
      end

      specify 'stub_plan_action' do
        action = create_action Support::DummyExample::WeightedPolling
        action.execution_plan.stub_planned_action(Support::DummyExample::Polling) do |sub_action|
          sub_action.define_singleton_method(:test) { "test" }
        end
        plan_action(action, {})
        stubbed_action = action.execution_plan.planned_plan_steps.first
        stubbed_action.test.must_equal "test"
      end

      specify '#run_action without suspend' do
        input  = { 'input' => 'input' }
        plan   = create_and_plan_action Support::DummyExample::WeightedPolling, input
        action = run_action plan

        action.must_be_kind_of Support::DummyExample::WeightedPolling
        action.phase.must_equal Action::Run
        action.input.must_equal input
        action.world.must_equal plan.world
        action.run_step_id.wont_equal action.plan_step_id
        action.state.must_equal :success
      end

      specify '#run_action with suspend' do
        input  = { 'input' => 'input' }
        plan   = create_and_plan_action Support::DummyExample::Polling, input
        action = run_action plan

        action.output.must_equal 'task' => { 'progress' => 0, 'done' => false }
        action.run_progress.must_equal 0

        3.times { progress_action_time action }
        action.output.must_equal('task' => { 'progress' => 30, 'done' => false } ,
                                 'poll_attempts' => {'total' => 2, 'failed'=> 0 })
        action.run_progress.must_equal 0.3

        run_action action, Dynflow::Action::Polling::Poll
        run_action action, Dynflow::Action::Polling::Poll
        action.output.must_equal('task' => { 'progress' => 50, 'done' => false },
                                 'poll_attempts' => {'total' => 4, 'failed' => 0 })
        action.run_progress.must_equal 0.5

        5.times { progress_action_time action }


        action.output.must_equal('task' => { 'progress' => 100, 'done' => true },
                                 'poll_attempts' => {'total' => 9, 'failed' => 0 })
        action.run_progress.must_equal 1
      end

      specify '#finalize_action' do
        input                 = { 'input' => 'input' }
        plan                  = create_and_plan_action Support::DummyExample::WeightedPolling, input
        run                   = run_action plan
        $dummy_heavy_progress = false
        action                = finalize_action run

        action.must_be_kind_of Support::DummyExample::WeightedPolling
        action.phase.must_equal Action::Finalize
        action.input.must_equal input
        action.output.must_equal run.output
        action.world.must_equal plan.world
        action.finalize_step_id.wont_equal action.run_step_id
        action.state.must_equal :success

        $dummy_heavy_progress.must_equal 'dummy_heavy_progress'
      end
    end

    describe 'testing examples' do

      describe CWE::Commit do
        it 'plans' do
          action = create_and_plan_action CWE::Commit, sha = 'commit-sha'

          action.input.must_equal({})
          refute_run_phase action
          refute_finalize_phase action

          assert_action_planed action, CWE::Ci
          assert_action_planed_with action, CWE::Review do |_, name, _|
            name == 'Morfeus'
          end
          assert_action_planed_with action, CWE::Review, sha, 'Neo', true
        end
      end

      describe CWE::Review do
        let(:plan_input) { ['sha', 'name', true] }
        let(:input) { { commit: 'sha', reviewer: 'name', result: true } }
        let(:planned_action) { create_and_plan_action CWE::Review, *plan_input }
        let(:runned_action) { run_action planned_action }

        it 'plans' do
          planned_action.input.must_equal input.stringify_keys
          assert_run_phase planned_action, { commit: "sha", reviewer: "name", result: true}
          refute_finalize_phase planned_action

          planned_action.execution_plan.planned_plan_steps.must_be_empty
        end

        it 'runs' do
          runned_action.output.fetch(:passed).must_equal runned_action.input.fetch(:result)
        end
      end

      describe CWE::Merge do
        let(:plan_input) { { commit: 'sha', ci_result: true, review_results: [true, true] } }
        let(:input) { plan_input }
        let(:planned_action) { create_and_plan_action CWE::Merge, plan_input }
        let(:runned_action) { run_action planned_action }

        it 'plans' do
          assert_run_phase planned_action do |input|
            input[:commit].must_equal "sha"
          end
          refute_finalize_phase planned_action

          planned_action.execution_plan.planned_plan_steps.must_be_empty
        end

        it 'runs' do
          runned_action.output.fetch(:passed).must_equal true
        end

        describe 'when something fails' do
          def plan_input
            super.update review_results: [true, false]
          end

          it 'runs' do
            runned_action.output.fetch(:passed).must_equal false
          end
        end
      end
    end
  end

end
