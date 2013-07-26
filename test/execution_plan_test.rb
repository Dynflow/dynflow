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

      def self.test_execution_plan(plan, run)
        it 'all plan steps are in success state' do
          execution_plan.plan_steps.all? { |id, plan_step| plan_step.state.must_equal :success }
        end

        it 'constructs the plan of actions to be executed in run phase' do
          assert_run_flow dedent(plan), execution_plan
        end

        it 'executes the run steps' do
          result = world.execute(execution_plan).value
          raise result if result.is_a? Exception

          assert_run_flow dedent(run), execution_plan
        end
      end

      describe 'single dependencies' do
        let :execution_plan do
          ExecutionPlan.new(world, CodeWorkflowExample::IncommingIssues).tap do |plan|
            plan.plan(issues_data)
          end
        end

        test_execution_plan <<-PLAN, <<-RUN
          Dynflow::Flows::Concurrence
            Dynflow::Flows::Sequence
              4: Triage(pending) {"author"=>"Peter Smith", "text"=>"Failing test"}
              6: UpdateIssue(pending) {"triage_input"=>{"author"=>"Peter Smith", "text"=>"Failing test"}, "triage_output"=>Step(4).output}
              8: NotifyAssignee(pending) {"triage"=>Step(4).output}
            Dynflow::Flows::Sequence
              11: Triage(pending) {"author"=>"John Doe", "text"=>"Internal server error"}
              13: UpdateIssue(pending) {"triage_input"=>{"author"=>"John Doe", "text"=>"Internal server error"}, "triage_output"=>Step(11).output}
              15: NotifyAssignee(pending) {"triage"=>Step(11).output}
        PLAN
          Dynflow::Flows::Concurrence
            Dynflow::Flows::Sequence
              4: Triage(success) {"author"=>"Peter Smith", "text"=>"Failing test"} --> {\"ok\"=>true}
              6: UpdateIssue(success) {"triage_input"=>{"author"=>"Peter Smith", "text"=>"Failing test"}, "triage_output"=>Step(4).output} --> {}
              8: NotifyAssignee(success) {"triage"=>Step(4).output} --> {}
            Dynflow::Flows::Sequence
              11: Triage(success) {"author"=>"John Doe", "text"=>"Internal server error"} --> {\"ok\"=>true}
              13: UpdateIssue(success) {"triage_input"=>{"author"=>"John Doe", "text"=>"Internal server error"}, "triage_output"=>Step(11).output} --> {}
              15: NotifyAssignee(success) {"triage"=>Step(11).output} --> {}
        RUN
      end

      describe 'multi dependencies' do
        let :execution_plan do
          ExecutionPlan.new(world, CodeWorkflowExample::Commit).tap do |plan|
            plan.plan('sha' => 'abc123')
          end
        end

        test_execution_plan <<-PLAN, <<-RUN
          Dynflow::Flows::Sequence
            Dynflow::Flows::Concurrence
              3: Ci(pending) {"commit"=>{"sha"=>"abc123"}}
              5: Review(pending) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Morfeus"}
              7: Review(pending) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Neo"}
            9: Merge(pending) {"commit"=>{"sha"=>"abc123"}, "ci_output"=>Step(3).output, "review_outputs"=>[Step(5).output, Step(7).output]}
        PLAN
          Dynflow::Flows::Sequence
            Dynflow::Flows::Concurrence
              3: Ci(success) {"commit"=>{"sha"=>"abc123"}} --> {}
              5: Review(success) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Morfeus"} --> {}
              7: Review(success) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Neo"} --> {}
            9: Merge(success) {"commit"=>{"sha"=>"abc123"}, "ci_output"=>Step(3).output, "review_outputs"=>[Step(5).output, Step(7).output]} --> {}
        RUN
      end

      describe 'sequence and concurrence keyword used' do
        let :execution_plan do
          ExecutionPlan.new(world, CodeWorkflowExample::FastCommit).tap do |plan|
            plan.plan('sha' => 'abc123')
          end
        end

        test_execution_plan <<-PLAN, <<-RUN
          Dynflow::Flows::Sequence
            Dynflow::Flows::Concurrence
              3: Ci(pending) {"commit"=>{"sha"=>"abc123"}}
              5: Review(pending) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Morfeus"}
            7: Merge(pending) {"commit"=>{"sha"=>"abc123"}}
        PLAN
          Dynflow::Flows::Sequence
            Dynflow::Flows::Concurrence
              3: Ci(success) {"commit"=>{"sha"=>"abc123"}} --> {}
              5: Review(success) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Morfeus"} --> {}
            7: Merge(success) {"commit"=>{"sha"=>"abc123"}} --> {}
        RUN
      end
    end
  end
end
