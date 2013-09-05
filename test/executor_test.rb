require_relative 'test_helper'
require_relative 'code_workflow_example'

module Dynflow
  module ExecutorTest
    describe "executor" do

      include PlanAssertions

      let :issues_data do
        [{ 'author' => 'Peter Smith', 'text' => 'Failing test' },
         { 'author' => 'John Doe', 'text' => 'Internal server error' }]
      end

      let :failing_issues_data do
        [{ 'author' => 'Peter Smith', 'text' => 'Failing test' },
         { 'author' => 'John Doe', 'text' => 'trolling' }]
      end

      let :execution_plan do
        world.plan(CodeWorkflowExample::IncomingIssues, issues_data)
      end

      let :failed_execution_plan do
        plan = world.plan(CodeWorkflowExample::IncomingIssues, failing_issues_data)
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

      let :world do
        SimpleWorld.new :executor_class => executor_class
      end

      describe "execution plan state" do

        describe "after planning" do

          it "is pending" do
            execution_plan.state.must_equal :pending
          end

        end

        describe "when being executed" do

          let :execution_plan do
            world.plan(CodeWorkflowExample::IncomingIssue, { 'text' => 'get a break' })
          end

          before do
            TestPause.setup
            world.execute(execution_plan.id)
          end

          after do
            TestPause.teardown
          end

          it "is running" do
            TestPause.when_paused do
              plan = world.persistence.load_execution_plan(execution_plan.id)
              plan.state.must_equal :running
            end
          end

          it "fails when trying to execute again" do
            TestPause.when_paused do
              error = world.execute(execution_plan.id).value
              assert error.is_a? Exception
              error.message.must_match(/already running/)
            end
          end
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

      describe "execution of run flow" do

        before do
          TestExecutionLog.setup
        end

        let :result do
          world.execute(execution_plan.id).value.tap do |result|
            raise result if result.is_a? Exception
          end
        end

        after do
          TestExecutionLog.teardown
        end

        let :persisted_plan do
          result
          world.persistence.load_execution_plan(execution_plan.id)
        end

        describe "action with empty flows" do

          let :execution_plan do
            world.plan(CodeWorkflowExample::Dummy, { :text => "dummy" }).tap do |plan|
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
            world.execute(execution_plan.id).value
            error = world.execute(execution_plan.id).value
            error.must_be_kind_of Exception
            error.message.must_match /it's stopped/
          end

        end

        describe 'action with empty run flow but some finalize flow' do

          let :execution_plan do
            world.plan(CodeWorkflowExample::DummyWithFinalize, { :text => "dummy" }).tap do |plan|
              assert_equal plan.run_flow.size, 0
              assert_equal plan.finalize_flow.size, 1
            end
          end

          it "doesn't cause problems" do
            result.result.must_equal :success
            result.state.must_equal :stopped
          end

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

          it "runs all the steps in the finalize flow" do
            assert_finalized(Dynflow::CodeWorkflowExample::IncomingIssues,
                             { "issues" => [{ "author" => "Peter Smith", "text" => "Failing test" }, { "author" => "John Doe", "text" => "Internal server error" }] })
            assert_finalized(Dynflow::CodeWorkflowExample::Triage,
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

      describe "re-execution of run flow after fix" do

        after do
          TestExecutionLog.teardown
        end

        let :resumed_execution_plan do
          failed_step = failed_execution_plan.steps.values.find do |step|
            step.state == :error
          end
          world.persistence.load_action(failed_step).tap do |action|
            action.input[:text] = "ok"
            world.persistence.save_action(failed_step, action)
          end
          TestExecutionLog.setup
          world.execute(failed_execution_plan.id).value
        end

        it "runs all the steps in the run flow" do
          resumed_execution_plan.state.must_equal :stopped
          resumed_execution_plan.result.must_equal :success

          run_triages = TestExecutionLog.run.find_all do |action_class, input|
            action_class == CodeWorkflowExample::Triage
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
          resumed_execution_plan.result.must_equal :success

          run_triages = TestExecutionLog.run.find_all do |action_class, input|
            action_class == CodeWorkflowExample::Triage
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
        let(:manager) { Executors::Parallel::FlowManager.new execution_plan, execution_plan.run_flow }

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

      describe 'Pool::RoundRobin' do
        let(:rr) { Dynflow::Executors::Parallel::Pool::RoundRobin.new }
        it do
          rr.next.must_be_nil
          rr.next.must_be_nil
          rr.must_be_empty
          rr.add 1
          rr.next.must_equal 1
          rr.next.must_equal 1
          rr.add 2
          rr.next.must_equal 2
          rr.next.must_equal 1
          rr.next.must_equal 2
          rr.delete 1
          rr.next.must_equal 2
          rr.next.must_equal 2
          rr.delete 2
          rr.next.must_be_nil
          rr.must_be_empty
        end
      end

      describe 'Pool::JobStorage' do
        FakeStep = Struct.new(:execution_plan_id)

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
  end
end
