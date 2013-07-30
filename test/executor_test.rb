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

      describe "execution of run flow" do

        before do
          result = world.execute(execution_plan.id).value
          raise result if result.is_a? Exception
        end

        let :persisted_plan do
          world.persistence.load_execution_plan(execution_plan.id)
        end

        it "runs all the step in the flow" do
          assert_run_flow <<-EXECUTED_RUN_FLOW, persisted_plan
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

      end
    end
  end
end



