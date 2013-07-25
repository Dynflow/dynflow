require 'test_helper'
require 'code_workflow_example'

module Dynflow
  module ExecutionPlanTest
    describe ExecutionPlan do

      include PlanAssertions

      let :world do
        SimpleWorld.new
      end

      let :issues_data do
        [
         { 'author' => 'Peter Smith', 'text' => 'Failing test' },
         { 'author' => 'John Doe', 'text' => 'Internal server error' }
        ]
      end

      describe 'single dependencies' do
        let :execution_plan do
          ExecutionPlan.new(world, CodeWorkflowExample::IncommingIssues).tap do |plan|
            plan.plan(issues_data)
          end
        end

        it 'constructs the plan of actions to be executed in run phase' do
          assert_run_plan <<EXPECTED, execution_plan
Dynflow::Flows::Concurrence
  Dynflow::Flows::Sequence
    4: Triage {"author"=>"Peter Smith", "text"=>"Failing test"}
    6: UpdateIssue {"triage_input"=>{"author"=>"Peter Smith", "text"=>"Failing test"}, "triage_output"=>Step(4).output}
    8: NotifyAssignee {:triage=>Step(4).output}
  Dynflow::Flows::Sequence
    11: Triage {"author"=>"John Doe", "text"=>"Internal server error"}
    13: UpdateIssue {"triage_input"=>{"author"=>"John Doe", "text"=>"Internal server error"}, "triage_output"=>Step(11).output}
    15: NotifyAssignee {:triage=>Step(11).output}
EXPECTED
        end

      end

      describe 'multi dependencies' do
        let :execution_plan do
          ExecutionPlan.new(world, CodeWorkflowExample::Commit).tap do |plan|
            plan.plan('sha' => 'abc123')
          end
        end

        it 'constructs the plan of actions to be executed in run phase' do
          assert_run_plan <<EXPECTED, execution_plan
Dynflow::Flows::Sequence
  Dynflow::Flows::Concurrence
    3: Ci {"commit"=>{"sha"=>"abc123"}}
    5: Review {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Morfeus"}
    7: Review {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Neo"}
  9: Merge {"commit"=>{"sha"=>"abc123"}, "ci_output"=>Step(3).output, "review_outputs"=>[Step(5).output, Step(7).output]}
EXPECTED
        end

      end

      describe 'sequence and concurrence keyword used' do
        let :execution_plan do
          ExecutionPlan.new(world, CodeWorkflowExample::FastCommit).tap do |plan|
            plan.plan('sha' => 'abc123')
          end
        end

        it 'constructs the plan of actions to be executed in run phase' do
          assert_run_plan <<EXPECTED, execution_plan
Dynflow::Flows::Sequence
  Dynflow::Flows::Concurrence
    3: Ci {"commit"=>{"sha"=>"abc123"}}
    5: Review {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Morfeus"}
  7: Merge {"commit"=>{"sha"=>"abc123"}}
EXPECTED
        end
      end
    end
  end
end
