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

      let :execution_plan do
        world.plan(CodeWorkflowExample::IncomingIssues, issues_data)
      end

      let :persisted_plan do
        world.persistence.load_execution_plan(execution_plan.id)
      end

      [Executors::PooledSequential, Executors::Parallel].each do |executor_class|
        describe executor_class.to_s do

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
                world.plan(CodeWorkflowExample::IncomingIssue, { 'text' => 'trolling' })
              end

              it "is paused" do
                f = world.execute(execution_plan.id)
                sleep 1
                f
                f.value.tap do |plan|
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
              assert_finalized(Dynflow::CodeWorkflowExample::IncomingIssues,
                               { "issues" => [{ "author" => "Peter Smith", "text" => "Failing test" },
                                              { "author" => "John Doe", "text" => "Internal server error" }] })
              assert_finalized(Dynflow::CodeWorkflowExample::Triage,
                               { "author" => "Peter Smith", "text" => "Failing test" })
            end

          end
        end
      end

      describe 'Parallel' do
        let :world do
          SimpleWorld.new :executor_class => Executors::Parallel
        end

        describe 'FlowManager' do
          let(:manager) { Executors::Parallel::FlowManager.new execution_plan, execution_plan.run_flow }
          let(:root) { manager.instance_variable_get(:@cursor) }

          describe 'what_is_next' do
            def assert_to_run(execute_ids, expected)
              execute_ids.each { |id| manager.cursor_index[id].flow_step_done(:success) }
              assert root.next_step_ids == Set.new(expected), root.to_hash.pretty_inspect
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

          describe 'waht_is_next_with_errors' do
            def assert_to_run(expected, execution, done = false)
              execution.each { |id, state| manager.cursor_index[id].flow_step_done(state ? :success : :error) }
              assert root.next_step_ids == Set.new(expected), root.to_hash.pretty_inspect
              root.done?.must_equal done
            end

            it { assert_to_run [4, 13], {} }
            it { assert_to_run [7, 13], 4 => true }
            it { assert_to_run [13], 4 => true, 7 => false }
            it { assert_to_run [16], 4 => true, 7 => false, 13 => true }
            it { assert_to_run [], { 4 => true, 7 => false, 13 => true, 16 => false }, true }
            it { assert_to_run [], { 4 => true, 7 => false, 13 => false }, true }
            it { assert_to_run [], { 4 => false, 13 => false }, true }
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
end



