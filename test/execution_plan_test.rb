require 'test_helper'

module Dynflow
  module ExecutionPlanTest
    describe ExecutionPlan do
      class IncommingIssues < Action

        def plan(issues)
          issues.each do |issue|
            plan_action(IncommingIssue, issue)
          end
          plan_self('issues' => issues)
        end

        input_format do
          param :issues, Array do
            param :author, String
            param :text, String
          end
        end

      end

      class IncommingIssue < Action

        def plan(issue)
          plan_self(issue)
          plan_action(Triage, issue)
        end

        input_format do
          param :author, String
          param :text, String
        end

      end

      class Triage < Action

        input_format do
          param :author, String
          param :text, String
        end

        output_format do
          param :assignee, String
          param :severity, %w[low medium high]
        end

        def run; end

      end

      class NotifyAssignee < Action

        def self.subscribe
          Triage
        end

        input_format do
          param :triage, String # TODO - connect to Triage output
        end

        def run; end
      end

      def assert_run_steps(expected, execution_plan)
        steps_string =  execution_plan.inspect_steps(execution_plan.run_steps)
        steps_string.gsub!(/^.*::/,'')
        steps_string.must_equal expected.chomp
      end

      let :issues_data do
        [
         { 'author' => 'Peter Smith', 'text' => 'Failing test' },
         { 'author' => 'John Doe', 'text' => 'Internal server error' }
        ]
      end

      let :execution_plan do
        IncommingIssues.plan(issues_data)
      end

      it 'includes only actions with run method defined in run steps' do
        actions_with_run = [Dynflow::ExecutionPlanTest::Triage,
                            Dynflow::ExecutionPlanTest::NotifyAssignee]
        execution_plan.run_steps.map(&:action_class).uniq.must_equal(actions_with_run)
      end

      it 'constructs the plan of actions to be executed in run phase' do
        assert_run_steps <<EXPECTED, execution_plan
Triage/Run: {"author"=>"Peter Smith", "text"=>"Failing test"}
NotifyAssignee/Run: {"author"=>"Peter Smith", "text"=>"Failing test"}
Triage/Run: {"author"=>"John Doe", "text"=>"Internal server error"}
NotifyAssignee/Run: {"author"=>"John Doe", "text"=>"Internal server error"}
EXPECTED
      end

    end
  end
end
