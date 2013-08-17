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

      [Executors::Parallel].each do |executor_class|
        describe executor_class.to_s do

          let :world do
            SimpleWorld.new :executor_class => executor_class
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

            let :persisted_plan do
              world.persistence.load_execution_plan(execution_plan.id)
            end

            describe "suspended action" do

              let :execution_plan do
                world.plan(CodeWorkflowExample::DummySuspended, {:external_task_id => "123"})
              end

              it "doesn't cause problems" do
                plan = world.execute(execution_plan.id).value
                plan.result.must_equal :success
                plan.state.must_equal :stopped
              end

            end
          end
        end
      end
    end
  end
end
