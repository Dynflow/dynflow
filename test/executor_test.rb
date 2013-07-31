require_relative 'test_helper'
require_relative 'code_workflow_example'

module Dynflow
  module ExecutorTest
    describe "executor" do

      include PlanAssertions

      let :world do
        SimpleWorld.new
      end

      let :issues_data do
        [{ 'author' => 'Peter Smith', 'text' => 'Failing test' },
         { 'author' => 'John Doe', 'text' => 'Internal server error' }]
      end

      let :execution_plan do
        world.plan(CodeWorkflowExample::IncommingIssues, issues_data)
      end

      let :persisted_plan do
        world.persistence.load_execution_plan(execution_plan.id)
      end

      describe "execution plan state" do

        describe "after planning" do

          it "is pending" do
            execution_plan.state.must_equal :pending
          end

        end

        describe "when being executed" do

          let :execution_plan do
            world.plan(CodeWorkflowExample::IncommingIssue, { 'text' => 'get a break' })
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
        end

        describe "when finished successfully" do

          it "is stopped" do
            world.execute(execution_plan.id).value.tap do |plan|
              plan.state.must_equal :stopped
            end
          end
        end

        describe "when finished with error" do
          let :execution_plan do
            world.plan(CodeWorkflowExample::IncommingIssue, { 'text' => 'trolling' })
          end

          it "is paused" do
            world.execute(execution_plan.id).value.tap do |plan|
              plan.state.must_equal :paused
            end
          end
        end
      end

      describe "execution of run flow" do

        before do
          TestExecutionLog.setup
          result = world.execute(execution_plan.id).value
          raise result if result.is_a? Exception
        end

        after do
          TestExecutionLog.teardown
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

        it "runs all the steps in the finalize flow" do
          assert_finalized(Dynflow::CodeWorkflowExample::IncommingIssues,
                           { "issues" => [{ "author" => "Peter Smith", "text" => "Failing test" },
                                          { "author" => "John Doe", "text" => "Internal server error" }] })
          assert_finalized(Dynflow::CodeWorkflowExample::Triage,
                           { "author" => "Peter Smith", "text" => "Failing test" })
        end

      end

      describe 'Parallel' do
        describe 'FlowManager' do
          let(:manager) { Executors::Parallel::FlowManager.new execution_plan, execution_plan.run_flow }
          let(:root) { manager.instance_variable_get(:@run_cursor) }
          it do
            root.to_hash.must_equal(
                children:       [{ children:       [],
                                   depends_on:     { children:       [],
                                                     depends_on:     { children:       [],
                                                                       depends_on:     nil,
                                                                       flow_step_id:   4,
                                                                       done:           false,
                                                                       flow_step_done: false },
                                                     flow_step_id:   7,
                                                     flow_step_done: false,
                                                     done:           false },
                                   flow_step_id:   9,
                                   done:           false,
                                   flow_step_done: false },
                                 { children:       [],
                                   depends_on:     { children:       [],
                                                     depends_on:     { children:       [],
                                                                       depends_on:     nil,
                                                                       flow_step_id:   13,
                                                                       done:           false,
                                                                       flow_step_done: false },
                                                     flow_step_id:   16,
                                                     done:           false,
                                                     flow_step_done: false },
                                   flow_step_id:   18,
                                   done:           false,
                                   flow_step_done: false }],
                depends_on:     nil,
                flow_step_id:   nil,
                done:           false,
                flow_step_done: false)
          end
          describe 'to_run' do
            def assert_to_run(execute_ids, expected)
              execute_ids.each { |id| manager.cursor_index[id].flow_step_done }
              root.to_run.must_equal Set.new(expected)
            end

            it { assert_to_run [], [4, 13] }
            it { assert_to_run [4], [7, 13] }
            it { assert_to_run [4, 7], [9, 13] }
            it { assert_to_run [4, 13], [7, 16] }
            it { assert_to_run [4, 13, 7], [9, 16] }
            it { assert_to_run [4, 13, 7, 9], [16] }
            it { assert_to_run [4, 13, 16, 7, 9], [18] }
            it { assert_to_run [4, 13, 16, 18, 7, 9], [] }
          end
        end
      end
    end
  end
end



