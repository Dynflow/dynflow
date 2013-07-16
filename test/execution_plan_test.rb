require 'test_helper'
require 'code_workflow_example'

module Dynflow
  module ExecutionPlanTest
    describe ExecutionPlan do

      include PlanAssertions

      let :issues_data do
        [
         { 'author' => 'Peter Smith', 'text' => 'Failing test' },
         { 'author' => 'John Doe', 'text' => 'Internal server error' }
        ]
      end

      describe 'single dependencies' do
        let :execution_plan do
          CodeWorkflowExample::IncommingIssues.plan(issues_data).execution_plan
        end

        it 'includes only actions with run method defined in run steps' do
          actions_with_run = [CodeWorkflowExample::Triage,
                              CodeWorkflowExample::UpdateIssue,
                              CodeWorkflowExample::NotifyAssignee]
          execution_plan.run_steps.map(&:action_class).uniq.must_equal(actions_with_run)
        end

        it 'constructs the plan of actions to be executed in run phase' do
          assert_run_plan <<EXPECTED, execution_plan
Dynflow::ExecutionPlan::Concurrence
  Dynflow::ExecutionPlan::Sequence
    Triage/RunStep({"author"=>"Peter Smith", "text"=>"Failing test"})
    UpdateIssue/RunStep({"triage_input"=>{"author"=>"Peter Smith", "text"=>"Failing test"}, "triage_output"=>Reference(Triage/RunStep({"author"=>"Peter Smith", "text"=>"Failing test"})/output)})
    NotifyAssignee/RunStep({"author"=>"Peter Smith", "text"=>"Failing test", "triage"=>Reference(Triage/RunStep({"author"=>"Peter Smith", "text"=>"Failing test"})/output)})
  Dynflow::ExecutionPlan::Sequence
    Triage/RunStep({"author"=>"John Doe", "text"=>"Internal server error"})
    UpdateIssue/RunStep({"triage_input"=>{"author"=>"John Doe", "text"=>"Internal server error"}, "triage_output"=>Reference(Triage/RunStep({"author"=>"John Doe", "text"=>"Internal server error"})/output)})
    NotifyAssignee/RunStep({"author"=>"John Doe", "text"=>"Internal server error", "triage"=>Reference(Triage/RunStep({"author"=>"John Doe", "text"=>"Internal server error"})/output)})
EXPECTED
        end

      end

      describe 'multi dependencies' do
        let :execution_plan do
          CodeWorkflowExample::Commit.plan('sha' => 'abc123').execution_plan
        end

        it 'constructs the plan of actions to be executed in run phase' do
          assert_run_plan <<EXPECTED, execution_plan
Dynflow::ExecutionPlan::Concurrence
  Dynflow::ExecutionPlan::Sequence
    Ci/RunStep({"commit"=>{"sha"=>"abc123"}})
    Review/RunStep({"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Morfeus"})
    Review/RunStep({"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Neo"})
    Merge/RunStep({"commit"=>{"sha"=>"abc123"}, "ci_output"=>Reference(Ci/RunStep({"commit"=>{"sha"=>"abc123"}})/output), "review_outputs"=>[Reference(Review/RunStep({"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Morfeus"})/output), Reference(Review/RunStep({"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Neo"})/output)]})
EXPECTED
        end

      end

    end
  end
end
