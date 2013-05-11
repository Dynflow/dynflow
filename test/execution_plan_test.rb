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

        def run; end

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

        def run; end

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

      it "builds the execution plan" do
        issues_data = [
                       { 'author' => 'Peter Smith', 'text' => 'Failing test' },
                       { 'author' => 'John Doe', 'text' => 'Internal server error' }
                      ]
        execution_plan = IncommingIssues.plan(issues_data)
        expected_plan_actions =
          [
           IncommingIssue.new("author"=>"Peter Smith", "text"=>"Failing test"),
           Triage.new("author"=>"Peter Smith", "text"=>"Failing test"),
           NotifyAssignee.new("author"=>"Peter Smith", "text"=>"Failing test"),
           IncommingIssue.new("author"=>"John Doe", "text"=>"Internal server error"),
           Triage.new("author"=>"John Doe", "text"=>"Internal server error"),
           NotifyAssignee.new("author"=>"John Doe", "text"=>"Internal server error"),
           IncommingIssues.new("issues"=>[{"author"=>"Peter Smith", "text"=>"Failing test"}, {"author"=>"John Doe", "text"=>"Internal server error"}])
          ]
        execution_plan.run_steps.map(&:action).must_equal expected_plan_actions
      end

    end
  end
end
