# -*- coding: utf-8 -*-
require_relative 'test_helper'

module Dynflow
  module ExecutorTest
    describe "executor" do

      include PlanAssertions

      let(:world) { WorldFactory.create_world }

      let :issues_data do
        [{ 'author' => 'Peter Smith', 'text' => 'Failing test' },
         { 'author' => 'John Doe', 'text' => 'Internal server error' }]
      end

      let :failing_issues_data do
        [{ 'author' => 'Peter Smith', 'text' => 'Failing test' },
         { 'author' => 'John Doe', 'text' => 'trolling' }]
      end

      let :finalize_failing_issues_data do
        [{ 'author' => 'Peter Smith', 'text' => 'Failing test' },
         { 'author' => 'John Doe', 'text' => 'trolling in finalize' }]
      end

      let :failed_execution_plan do
        plan = world.plan(Support::CodeWorkflowExample::IncomingIssues, failing_issues_data)
        plan = world.execute(plan.id).value
        plan.state.must_equal :paused
        plan
      end

      let :finalize_failed_execution_plan do
        plan = world.plan(Support::CodeWorkflowExample::IncomingIssues, finalize_failing_issues_data)
        plan = world.execute(plan.id).value
        plan.state.must_equal :paused
        plan
      end

      let :persisted_plan do
        world.persistence.load_execution_plan(execution_plan.id)
      end

      let :executor_class do
        Executors::Parallel
      end

      describe "execution plan state" do

        describe "after successful planning" do

          let :execution_plan do
            world.plan(Support::CodeWorkflowExample::IncomingIssues, issues_data)
          end

          it "is pending" do
            execution_plan.state.must_equal :planned
          end

          describe "when finished successfully" do
            it "is stopped" do
              world.execute(execution_plan.id).value.tap do |plan|
                plan.state.must_equal :stopped
              end
            end
          end

          describe "when finished with error" do
            it "is paused" do
              world.execute(failed_execution_plan.id).value.tap do |plan|
                plan.state.must_equal :paused
              end
            end
          end
        end

        describe "after error in planning" do

          class FailingAction < Dynflow::Action
            def plan
              raise "I failed"
            end
          end

          let :execution_plan do
            world.plan(FailingAction)
          end

          it "is stopped" do
            execution_plan.state.must_equal :stopped
          end

        end

        describe "when being executed" do

          let :execution_plan do
            world.plan(Support::CodeWorkflowExample::IncomingIssue, { 'text' => 'get a break' })
          end

          before do
            TestPause.setup
            @execution = world.execute(execution_plan.id)
          end

          after do
            @execution.wait
            TestPause.teardown
          end

          it "is running" do
            TestPause.when_paused do
              plan = world.persistence.load_execution_plan(execution_plan.id)
              plan.state.must_equal :running
              triage = plan.run_steps.find do |s|
                s.action_class == Support::CodeWorkflowExample::Triage
              end
              triage.state.must_equal :running
              world.persistence.
                  load_step(triage.execution_plan_id, triage.id, world).
                  state.must_equal :running
            end
          end

          it "fails when trying to execute again" do
            TestPause.when_paused do
              assert_raises(Dynflow::Error) { world.execute(execution_plan.id).value! }
            end
          end
        end
      end

      describe "execution of run flow" do

        before do
          TestExecutionLog.setup
        end

        let :result do
          world.execute(execution_plan.id).value!
        end

        after do
          TestExecutionLog.teardown
        end

        def persisted_plan
          result
          super
        end

        describe 'cancellable action' do
          describe 'successful' do
            let :execution_plan do
              world.plan(Support::CodeWorkflowExample::CancelableSuspended, {})
            end

            it "doesn't cause problems" do
              result.result.must_equal :success
              result.state.must_equal :stopped
            end
          end

          describe 'canceled' do
            let :execution_plan do
              world.plan(Support::CodeWorkflowExample::CancelableSuspended, { text: 'cancel-self' })
            end

            it 'cancels' do
              result.result.must_equal :success
              result.state.must_equal :stopped
              action = world.persistence.load_action result.steps[2]
              action.output[:task][:progress].must_equal 30
              action.output[:task][:cancelled].must_equal true
            end
          end

          describe 'canceled failed' do
            let :execution_plan do
              world.plan(Support::CodeWorkflowExample::CancelableSuspended, { text: 'cancel-fail cancel-self' })
            end

            it 'fails' do
              result.result.must_equal :error
              result.state.must_equal :paused
              step = result.steps[2]
              step.error.message.must_equal 'action cancelled'
              action = world.persistence.load_action step
              action.output[:task][:progress].must_equal 30
            end
          end
        end

        describe 'suspended action' do
          describe 'handling errors in setup' do
            let :execution_plan do
              world.plan(Support::DummyExample::Polling,
                         external_task_id: '123',
                         text:             'troll setup')
            end

            it 'fails' do
              assert_equal :error, result.result
              assert_equal :paused, result.state
              assert_equal :error, result.run_steps.first.state
            end
          end

          describe 'running' do
            let :execution_plan do
              world.plan(Support::DummyExample::Polling, { :external_task_id => '123' })
            end

            it "doesn't cause problems" do
              result.result.must_equal :success
              result.state.must_equal :stopped
            end

            it 'does set times' do
              result.started_at.wont_be_nil
              result.ended_at.wont_be_nil
              result.execution_time.must_be :<, result.real_time
              result.execution_time.must_equal(
                  result.steps.inject(0) { |sum, (_, step)| sum + step.execution_time })

              plan_step = result.steps[1]
              plan_step.started_at.wont_be_nil
              plan_step.ended_at.wont_be_nil
              plan_step.execution_time.must_equal plan_step.real_time

              run_step = result.steps[2]
              run_step.started_at.wont_be_nil
              run_step.ended_at.wont_be_nil
              run_step.execution_time.must_be :<, run_step.real_time
            end
          end

          describe 'progress' do
            before do
              TestPause.setup
              @running_plan = world.execute(execution_plan.id)
            end

            after do
              @running_plan.wait
              TestPause.teardown
            end

            describe 'plan with one action' do
              let :execution_plan do
                world.plan(Support::DummyExample::Polling,
                           { external_task_id: '123',
                             text:             'pause in progress 20%' })
              end

              it 'determines the progress of the execution plan in percents' do
                TestPause.when_paused do
                  plan = world.persistence.load_execution_plan(execution_plan.id)
                  plan.progress.round(2).must_equal 0.2
                end
              end
            end

            describe 'plan with more action' do
              let :execution_plan do
                world.plan(Support::DummyExample::WeightedPolling,
                           { external_task_id: '123',
                             text:             'pause in progress 20%' })
              end

              it 'takes the steps weight in account' do
                TestPause.when_paused do
                  plan = world.persistence.load_execution_plan(execution_plan.id)
                  plan.progress.round(2).must_equal 0.42
                end
              end
            end
          end

          describe 'works when resumed after error' do
            let :execution_plan do
              world.plan(Support::DummyExample::Polling,
                         { external_task_id: '123',
                           text:             'troll progress' })
            end

            specify do
              assert_equal :paused, result.state
              assert_equal :error, result.result
              assert_equal :error, result.run_steps.first.state

              ep = world.execute(result.id).value
              assert_equal :stopped, ep.state
              assert_equal :success, ep.result
              assert_equal :success, ep.run_steps.first.state
            end
          end

        end

        describe "action with empty flows" do

          let :execution_plan do
            world.plan(Support::CodeWorkflowExample::Dummy, { :text => "dummy" }).tap do |plan|
              assert_equal plan.run_flow.size, 0
              assert_equal plan.finalize_flow.size, 0
            end.tap do |w|
              w
            end
          end

          it "doesn't cause problems" do
            result.result.must_equal :success
            result.state.must_equal :stopped
          end

          it 'will not run again' do
            world.execute(execution_plan.id)
            assert_raises(Dynflow::Error) { world.execute(execution_plan.id).value! }
          end

        end

        describe 'action with empty run flow but some finalize flow' do

          let :execution_plan do
            world.plan(Support::CodeWorkflowExample::DummyWithFinalize, { :text => "dummy" }).tap do |plan|
              assert_equal plan.run_flow.size, 0
              assert_equal plan.finalize_flow.size, 1
            end
          end

          it "doesn't cause problems" do
            result.result.must_equal :success
            result.state.must_equal :stopped
          end

        end

        describe 'running' do
          let :execution_plan do
            world.plan(Support::CodeWorkflowExample::IncomingIssues, issues_data)
          end

          it "runs all the steps in the run flow" do
            assert_run_flow <<-EXECUTED_RUN_FLOW, persisted_plan
              Dynflow::Flows::Concurrence
                Dynflow::Flows::Sequence
                  4: Triage(success) {"author"=>"Peter Smith", "text"=>"Failing test"} --> {"classification"=>{"assignee"=>"John Doe", "severity"=>"medium"}}
                  7: UpdateIssue(success) {"author"=>"Peter Smith", "text"=>"Failing test", "assignee"=>"John Doe", "severity"=>"medium"} --> {}
                  9: NotifyAssignee(success) {"triage"=>{"classification"=>{"assignee"=>"John Doe", "severity"=>"medium"}}} --> {}
                Dynflow::Flows::Sequence
                  13: Triage(success) {"author"=>"John Doe", "text"=>"Internal server error"} --> {"classification"=>{"assignee"=>"John Doe", "severity"=>"medium"}}
                  16: UpdateIssue(success) {"author"=>"John Doe", "text"=>"Internal server error", "assignee"=>"John Doe", "severity"=>"medium"} --> {}
                  18: NotifyAssignee(success) {"triage"=>{"classification"=>{"assignee"=>"John Doe", "severity"=>"medium"}}} --> {}
            EXECUTED_RUN_FLOW
          end
        end

      end

      describe "execution of finalize flow" do
        before do
          TestExecutionLog.setup
          result = world.execute(execution_plan.id).value
          raise result if result.is_a? Exception
        end

        after do
          TestExecutionLog.teardown
        end

        describe "when run flow successful" do
          let :execution_plan do
            world.plan(Support::CodeWorkflowExample::IncomingIssues, issues_data)
          end

          it "runs all the steps in the finalize flow" do
            assert_finalized(Support::CodeWorkflowExample::IncomingIssues,
                             { "issues" => [{ "author" => "Peter Smith", "text" => "Failing test" }, { "author" => "John Doe", "text" => "Internal server error" }] })
            assert_finalized(Support::CodeWorkflowExample::Triage,
                             { "author" => "Peter Smith", "text" => "Failing test" })
          end
        end

        describe "when run flow failed" do
          let :execution_plan do
            failed_execution_plan
          end

          it "doesn't run the steps in the finalize flow" do
            TestExecutionLog.finalize.size.must_equal 0
          end
        end

      end

      describe "re-execution of run flow after fix in run phase" do

        after do
          TestExecutionLog.teardown
        end

        let :resumed_execution_plan do
          failed_step = failed_execution_plan.steps.values.find do |step|
            step.state == :error
          end
          world.persistence.load_action(failed_step).tap do |action|
            action.input[:text] = "ok"
            world.persistence.save_action(failed_step.execution_plan_id, action)
          end
          TestExecutionLog.setup
          world.execute(failed_execution_plan.id).value
        end

        it "runs all the steps in the run flow" do
          resumed_execution_plan.state.must_equal :stopped
          resumed_execution_plan.result.must_equal :success

          run_triages = TestExecutionLog.run.find_all do |action_class, input|
            action_class == Support::CodeWorkflowExample::Triage
          end
          run_triages.size.must_equal 1

          assert_run_flow <<-EXECUTED_RUN_FLOW, resumed_execution_plan
        Dynflow::Flows::Concurrence
          Dynflow::Flows::Sequence
            4: Triage(success) {\"author\"=>\"Peter Smith\", \"text\"=>\"Failing test\"} --> {\"classification\"=>{\"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"}}
            7: UpdateIssue(success) {\"author\"=>\"Peter Smith\", \"text\"=>\"Failing test\", \"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"} --> {}
            9: NotifyAssignee(success) {\"triage\"=>{\"classification\"=>{\"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"}}} --> {}
          Dynflow::Flows::Sequence
            13: Triage(success) {\"author\"=>\"John Doe\", \"text\"=>\"ok\"} --> {\"classification\"=>{\"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"}}
            16: UpdateIssue(success) {\"author\"=>\"John Doe\", \"text\"=>\"trolling\", \"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"} --> {}
            18: NotifyAssignee(success) {\"triage\"=>{\"classification\"=>{\"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"}}} --> {}
          EXECUTED_RUN_FLOW
        end

      end

      describe "re-execution of run flow after fix in finalize phase" do

        after do
          TestExecutionLog.teardown
        end

        let :resumed_execution_plan do
          failed_step = finalize_failed_execution_plan.steps.values.find do |step|
            step.state == :error
          end
          world.persistence.load_action(failed_step).tap do |action|
            action.input[:text] = "ok"
            world.persistence.save_action(failed_step.execution_plan_id, action)
          end
          TestExecutionLog.setup
          world.execute(finalize_failed_execution_plan.id).value
        end

        it "runs all the steps in the finalize flow" do
          resumed_execution_plan.state.must_equal :stopped
          resumed_execution_plan.result.must_equal :success

          run_triages = TestExecutionLog.finalize.find_all do |action_class, input|
            action_class == Support::CodeWorkflowExample::Triage
          end
          run_triages.size.must_equal 2

          assert_finalize_flow <<-EXECUTED_RUN_FLOW, resumed_execution_plan
            Dynflow::Flows::Sequence
              5: Triage(success) {\"author\"=>\"Peter Smith\", \"text\"=>\"Failing test\"} --> {\"classification\"=>{\"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"}}
              10: NotifyAssignee(success) {\"triage\"=>{\"classification\"=>{\"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"}}} --> {}
              14: Triage(success) {\"author\"=>\"John Doe\", \"text\"=>\"ok\"} --> {\"classification\"=>{\"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"}}
              19: NotifyAssignee(success) {\"triage\"=>{\"classification\"=>{\"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"}}} --> {}
              20: IncomingIssues(success) {\"issues\"=>[{\"author\"=>\"Peter Smith\", \"text\"=>\"Failing test\"}, {\"author\"=>\"John Doe\", \"text\"=>\"trolling in finalize\"}]} --> {}
          EXECUTED_RUN_FLOW
        end

      end

      describe "re-execution of run flow after skipping" do

        after do
          TestExecutionLog.teardown
        end

        let :resumed_execution_plan do
          failed_step = failed_execution_plan.steps.values.find do |step|
            step.state == :error
          end
          failed_execution_plan.skip(failed_step)
          TestExecutionLog.setup
          world.execute(failed_execution_plan.id).value
        end

        it "runs all pending steps except skipped" do
          resumed_execution_plan.state.must_equal :stopped
          resumed_execution_plan.result.must_equal :warning

          run_triages = TestExecutionLog.run.find_all do |action_class, input|
            action_class == Support::CodeWorkflowExample::Triage
          end
          run_triages.size.must_equal 0

          assert_run_flow <<-EXECUTED_RUN_FLOW, resumed_execution_plan
        Dynflow::Flows::Concurrence
          Dynflow::Flows::Sequence
            4: Triage(success) {\"author\"=>\"Peter Smith\", \"text\"=>\"Failing test\"} --> {\"classification\"=>{\"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"}}
            7: UpdateIssue(success) {\"author\"=>\"Peter Smith\", \"text\"=>\"Failing test\", \"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"} --> {}
            9: NotifyAssignee(success) {\"triage\"=>{\"classification\"=>{\"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"}}} --> {}
          Dynflow::Flows::Sequence
            13: Triage(skipped) {\"author\"=>\"John Doe\", \"text\"=>\"trolling\"} --> {}
            16: UpdateIssue(skipped) {\"author\"=>\"John Doe\", \"text\"=>\"trolling\", \"assignee\"=>Step(13).output[:classification][:assignee], \"severity\"=>Step(13).output[:classification][:severity]} --> {}
            18: NotifyAssignee(skipped) {\"triage\"=>Step(13).output} --> {}
          EXECUTED_RUN_FLOW

          assert_finalize_flow <<-FINALIZE_FLOW, resumed_execution_plan
        Dynflow::Flows::Sequence
          5: Triage(success) {\"author\"=>\"Peter Smith\", \"text\"=>\"Failing test\"} --> {\"classification\"=>{\"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"}}
          10: NotifyAssignee(success) {\"triage\"=>{\"classification\"=>{\"assignee\"=>\"John Doe\", \"severity\"=>\"medium\"}}} --> {}
          14: Triage(skipped) {\"author\"=>\"John Doe\", \"text\"=>\"trolling\"} --> {}
          19: NotifyAssignee(skipped) {\"triage\"=>Step(13).output} --> {}
          20: IncomingIssues(success) {\"issues\"=>[{\"author\"=>\"Peter Smith\", \"text\"=>\"Failing test\"}, {\"author\"=>\"John Doe\", \"text\"=>\"trolling\"}]} --> {}
          FINALIZE_FLOW

        end
      end

      describe 'FlowManager' do
        let :execution_plan do
          world.plan(Support::CodeWorkflowExample::IncomingIssues, issues_data)
        end

        let(:manager) { Director::FlowManager.new execution_plan, execution_plan.run_flow }

        def assert_next_steps(expected_next_step_ids, finished_step_id = nil, success = true)
          if finished_step_id
            step       = manager.execution_plan.steps[finished_step_id]
            next_steps = manager.cursor_index[step.id].what_is_next(step, success)
          else
            next_steps = manager.start
          end
          next_step_ids = next_steps.map(&:id)
          assert_equal Set.new(expected_next_step_ids), Set.new(next_step_ids)
        end

        describe 'what_is_next' do
          it 'returns next steps after required steps were finished' do
            assert_next_steps([4, 13])
            assert_next_steps([7], 4)
            assert_next_steps([9], 7)
            assert_next_steps([], 9)
            assert_next_steps([16], 13)
            assert_next_steps([18], 16)
            assert_next_steps([], 18)
            assert manager.done?
          end
        end

        describe 'what_is_next with errors' do

          it "doesn't return next steps if requirements failed" do
            assert_next_steps([4, 13])
            assert_next_steps([], 4, false)
          end

          it "is not done while other steps can be finished" do
            assert_next_steps([4, 13])
            assert_next_steps([], 4, false)
            assert !manager.done?
            assert_next_steps([], 13, false)
            assert manager.done?
          end
        end

      end

      describe 'Pool::JobStorage' do
        FakeStep ||= Struct.new(:execution_plan_id)

        let(:storage) { Dynflow::Executors::Parallel::Pool::JobStorage.new }
        it do
          storage.must_be_empty
          storage.pop.must_be_nil
          storage.pop.must_be_nil

          storage.add s = FakeStep.new(1)
          storage.pop.must_equal s
          storage.must_be_empty
          storage.pop.must_be_nil

          storage.add s11 = FakeStep.new(1)
          storage.add s12 = FakeStep.new(1)
          storage.add s13 = FakeStep.new(1)
          storage.add s21 = FakeStep.new(2)
          storage.add s22 = FakeStep.new(2)
          storage.add s31 = FakeStep.new(3)

          storage.pop.must_equal s21
          storage.pop.must_equal s31
          storage.pop.must_equal s11
          storage.pop.must_equal s22
          storage.pop.must_equal s12
          storage.pop.must_equal s13

          storage.must_be_empty
          storage.pop.must_be_nil
        end
      end

    end

    describe 'termination' do
      let(:world) { WorldFactory.create_world }

      it 'waits for currently running actions' do
        $slow_actions_done = 0
        running = world.trigger(Support::DummyExample::Slow, 1)
        suspended = world.trigger(Support::DummyExample::EventedAction, :timeout => 3 )
        sleep 0.2
        world.terminate.wait
        $slow_actions_done.must_equal 1
        [running, suspended].each do |triggered|
          plan = world.persistence.load_execution_plan(triggered.id)
          plan.state.must_equal :paused
          plan.result.must_equal :pending
        end
      end

      describe 'before_termination hooks' do
        it 'runs before temination hooks' do
          hook_run = false
          world.before_termination { hook_run = true }
          world.terminate.wait
          assert hook_run
        end

        it 'continues when some hook fails' do
          run_hooks, failed_hooks = [], []
          world.before_termination { run_hooks << 1 }
          world.before_termination { run_hooks << 2; failed_hooks << 2; raise 'error' }
          world.before_termination { run_hooks << 3 }
          world.terminate.wait
          run_hooks.must_equal [1, 2, 3]
          failed_hooks.must_equal [2]
        end
      end

      it 'does not accept new work' do
        assert world.terminate.wait
        result = world.trigger(Support::DummyExample::Slow, 0.02)
        result.must_be :planned?
        result.finished.wait
        assert result.finished.failed?
        result.finished.reason.must_be_kind_of Concurrent::Actor::ActorTerminated
      end

      it 'it terminates when no work right after initialization' do
        assert world.terminate.wait
      end

      it 'second terminate works' do
        assert world.terminate.wait
        assert world.terminate.wait
      end

      it 'second terminate works concurrently' do
        assert [world.terminate, world.terminate].map(&:value).all?
      end
    end

  end
end
