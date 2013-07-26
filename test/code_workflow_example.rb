module Dynflow
  module CodeWorkflowExample

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

      def plan(issue)
        triage = plan_self(issue)
        plan_action(UpdateIssue,
                    'triage_input'  => triage.input,
                    'triage_output' => triage.output)
      end

      input_format do
        param :author, String
        param :text, String
      end

      output_format do
        param :assignee, String
        param :severity, %w[low medium high]
      end

      def run
        self.output = { ok: true }
      end

    end

    class UpdateIssue < Action

      input_format do
        param :triage_input, Triage.input_format
        param :triage_output, Triage.output_format
      end

      def run
      end
    end

    class NotifyAssignee < Action

      def self.subscribe
        Triage
      end

      input_format do
        param :triage, Triage.output_format
      end

      def plan(*args)
        plan_self(:triage => trigger.output)
      end

      def run
      end
    end

    class Commit < Action

      def plan(commit)
        ci      = plan_action(Ci, 'commit' => commit)
        review1 = plan_action(Review, 'commit' => commit, 'reviewer' => 'Morfeus')
        review2 = plan_action(Review, 'commit' => commit, 'reviewer' => 'Neo')
        plan_action(Merge,
                    'commit'         => commit,
                    'ci_output'      => ci.output,
                    'review_outputs' => [review1.output, review2.output])
      end

      input_format do
        param :sha, String
      end

    end

    class FastCommit < Action

      def plan(commit)
        sequence do
          concurrence do
            plan_action(Ci, 'commit' => commit)
            plan_action(Review, 'commit' => commit, 'reviewer' => 'Morfeus')
          end

          plan_action(Merge, 'commit' => commit)
        end
      end

      input_format do
        param :sha, String
      end

    end

    class Ci < Action

      input_format do
        param :commit, Commit.input_format
      end

      output_format do
        param :passed, :boolean
      end

      def run
      end
    end

    class Review < Action

      input_format do
        param :reviewer, String
        param :commit, Commit.input_format
      end

      output_format do
        param :passed, :boolean
      end

      def run
      end
    end

    class Merge < Action

      input_format do
        param :commit, Commit.input_format
        param :ci_output, Ci.output_format
        param :review_outputs, array_of(Review.output_format)
      end

      def run
      end
    end

  end
end
