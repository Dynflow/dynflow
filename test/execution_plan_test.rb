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

      def self.test_execution_plan(plan_steps, planned_run_flow, executed_run_flow)
        it 'all plan steps are in success state' do
          execution_plan.plan_steps.all? { |id, plan_step| plan_step.state.must_equal :success }
        end

        it 'stores the information about the sub actions' do
          assert_plan_steps plan_steps, execution_plan
        end

        it 'constructs the plan of actions to be executed in run phase' do
          assert_run_flow planned_run_flow, execution_plan
        end

        it 'executes the run steps' do
          result = world.execute(execution_plan.id).value
          raise result if result.is_a? Exception

          # TODO use Persistence
          assert_run_flow(executed_run_flow,
                          ExecutionPlan.from_hash(
                              world.persistence_adapter.load_execution_plan(execution_plan.id),
                              world))
        end
      end

      describe 'serialization' do

        let :execution_plan do
          world.plan(CodeWorkflowExample::FastCommit, 'sha' => 'abc123')
        end

        let :deserialized_execution_plan do
          # TODO use Persistence
          ExecutionPlan.from_hash(
              world.persistence_adapter.load_execution_plan(execution_plan.id),
              world)
        end

        describe 'serialized execution plan' do

          before { execution_plan.persist }

          it 'restores the plan properly' do
            deserialized_execution_plan.id.must_equal execution_plan.id

            assert_plan_steps_equal execution_plan, deserialized_execution_plan
            assert_run_flow_equal execution_plan, deserialized_execution_plan
          end

        end

      end

      describe 'single dependencies' do
        let :execution_plan do
          world.plan(CodeWorkflowExample::IncommingIssues, issues_data)
        end

        test_execution_plan <<-PLAN_STEPS, <<-PLANNED_RUN_FLOW, <<-EXECUTED_RUN_FLOW
          IncommingIssues
            IncommingIssue
              Triage
                UpdateIssue
                NotifyAssignee
            IncommingIssue
              Triage
                UpdateIssue
                NotifyAssignee
        PLAN_STEPS
          Dynflow::Flows::Concurrence
            Dynflow::Flows::Sequence
              4: Triage(pending) {"author"=>"Peter Smith", "text"=>"Failing test"}
              6: UpdateIssue(pending) {"triage_input"=>{"author"=>"Peter Smith", "text"=>"Failing test"}, "triage_output"=>Step(4).output}
              8: NotifyAssignee(pending) {"triage"=>Step(4).output}
            Dynflow::Flows::Sequence
              11: Triage(pending) {"author"=>"John Doe", "text"=>"Internal server error"}
              13: UpdateIssue(pending) {"triage_input"=>{"author"=>"John Doe", "text"=>"Internal server error"}, "triage_output"=>Step(11).output}
              15: NotifyAssignee(pending) {"triage"=>Step(11).output}
        PLANNED_RUN_FLOW
          Dynflow::Flows::Concurrence
            Dynflow::Flows::Sequence
              4: Triage(success) {"author"=>"Peter Smith", "text"=>"Failing test"} --> {\"ok\"=>true}
              6: UpdateIssue(success) {"triage_input"=>{"author"=>"Peter Smith", "text"=>"Failing test"}, "triage_output"=>Step(4).output} --> {}
              8: NotifyAssignee(success) {"triage"=>Step(4).output} --> {}
            Dynflow::Flows::Sequence
              11: Triage(success) {"author"=>"John Doe", "text"=>"Internal server error"} --> {\"ok\"=>true}
              13: UpdateIssue(success) {"triage_input"=>{"author"=>"John Doe", "text"=>"Internal server error"}, "triage_output"=>Step(11).output} --> {}
              15: NotifyAssignee(success) {"triage"=>Step(11).output} --> {}
        EXECUTED_RUN_FLOW
      end

      describe 'multi dependencies' do
        let :execution_plan do
          world.plan(CodeWorkflowExample::Commit, 'sha' => 'abc123')
        end

        test_execution_plan <<-PLAN_STEPS, <<-PLANNED_RUN_FLOW, <<-EXECUTED_RUN_FLOW
          Commit
            Ci
            Review
            Review
            Merge
        PLAN_STEPS
          Dynflow::Flows::Sequence
            Dynflow::Flows::Concurrence
              3: Ci(pending) {"commit"=>{"sha"=>"abc123"}}
              5: Review(pending) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Morfeus"}
              7: Review(pending) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Neo"}
            9: Merge(pending) {"commit"=>{"sha"=>"abc123"}, "ci_output"=>Step(3).output, "review_outputs"=>[Step(5).output, Step(7).output]}
        PLANNED_RUN_FLOW
          Dynflow::Flows::Sequence
            Dynflow::Flows::Concurrence
              3: Ci(success) {"commit"=>{"sha"=>"abc123"}} --> {}
              5: Review(success) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Morfeus"} --> {}
              7: Review(success) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Neo"} --> {}
            9: Merge(success) {"commit"=>{"sha"=>"abc123"}, "ci_output"=>Step(3).output, "review_outputs"=>[Step(5).output, Step(7).output]} --> {}
        EXECUTED_RUN_FLOW
      end

      describe 'sequence and concurrence keyword used' do
        let :execution_plan do
          world.plan(CodeWorkflowExample::FastCommit, 'sha' => 'abc123')
        end

        test_execution_plan <<-PLAN_STEPS, <<-PLANNED_RUN_FLOW, <<-EXECUTED_RUN_FLOW
          FastCommit
            Ci
            Review
            Merge
        PLAN_STEPS
          Dynflow::Flows::Sequence
            Dynflow::Flows::Concurrence
              3: Ci(pending) {"commit"=>{"sha"=>"abc123"}}
              5: Review(pending) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Morfeus"}
            7: Merge(pending) {"commit"=>{"sha"=>"abc123"}}
        PLANNED_RUN_FLOW
          Dynflow::Flows::Sequence
            Dynflow::Flows::Concurrence
              3: Ci(success) {"commit"=>{"sha"=>"abc123"}} --> {}
              5: Review(success) {"commit"=>{"sha"=>"abc123"}, "reviewer"=>"Morfeus"} --> {}
            7: Merge(success) {"commit"=>{"sha"=>"abc123"}} --> {}
        EXECUTED_RUN_FLOW
      end
    end
  end
end
