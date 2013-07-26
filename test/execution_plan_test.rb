require_relative 'test_helper'
require_relative 'code_workflow_example'

module Dynflow
  module ExecutionPlanTest
    describe ExecutionPlan do

      include PlanAssertions

      let :world do
        SimpleWorld.new
      end

      let :issues_data do
        [{ 'author' => 'Peter Smith', 'text' => 'Failing test' },
         { 'author' => 'John Doe', 'text' => 'Internal server error' }]
      end

      def self.tests_after_plan
        it 'all plan steps are in success state' do
          execution_plan.plan_steps.all? { |id, plan_step| plan_step.state.must_equal :success }
        end
      end

      describe 'single dependencies' do
        let :execution_plan do
          ExecutionPlan.new(world, CodeWorkflowExample::IncommingIssues).tap do |plan|
            plan.plan(issues_data)
          end
        end

        it 'constructs the plan of actions to be executed in run phase' do
          assert_run_flow dedent(<<-EXPECTED), execution_plan
            Dynflow::Flows::Concurrence
              Dynflow::Flows::Sequence
                4: Triage(pending) {"author"=>"Peter Smith", "text"=>"Failing test"}
                6: UpdateIssue(pending) {"triage_input"=>{"author"=>"Peter Smith", "text"=>"Failing test"}, "triage_output"=>Step(4).output}
                8: NotifyAssignee(pending) {"triage"=>Step(4).output}
              Dynflow::Flows::Sequence
                11: Triage(pending) {"author"=>"John Doe", "text"=>"Internal server error"}
                13: UpdateIssue(pending) {"triage_input"=>{"author"=>"John Doe", "text"=>"Internal server error"}, "triage_output"=>Step(11).output}
                15: NotifyAssignee(pending) {"triage"=>Step(11).output}
          EXPECTED
        end

        tests_after_plan
      end

      describe 'multi dependencies' do
        let :execution_plan do
          ExecutionPlan.new(world, CodeWorkflowExample::Commit).tap do |plan|
            plan.plan('sha' => 'abc123')
          end
        end

        it 'constructs the plan of actions to be executed in run phase' do
          assert_run_flow dedent(<<-EXPECTED), execution_plan
            Dynflow::Flows::Sequence
              Dynflow::Flows::Concurrence
                3: Ci(pending) {"commit"=>{"sha"=>"abc123"}}
                5: Review(pending) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Morfeus"}
                7: Review(pending) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Neo"}
              9: Merge(pending) {"commit"=>{"sha"=>"abc123"}, "ci_output"=>Step(3).output, "review_outputs"=>[Step(5).output, Step(7).output]}
          EXPECTED
        end

        tests_after_plan
      end

      describe 'sequence and concurrence keyword used' do
        let :execution_plan do
          ExecutionPlan.new(world, CodeWorkflowExample::FastCommit).tap do |plan|
            plan.plan('sha' => 'abc123')
          end
        end

        it 'constructs the plan of actions to be executed in run phase' do
          assert_run_flow dedent(<<-EXPECTED), execution_plan
            Dynflow::Flows::Sequence
              Dynflow::Flows::Concurrence
                3: Ci(pending) {"commit"=>{"sha"=>"abc123"}}
                5: Review(pending) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Morfeus"}
              7: Merge(pending) {"commit"=>{"sha"=>"abc123"}}
          EXPECTED
        end

        tests_after_plan
      end
    end
  end
end
