require 'logger'

module Support
  module CodeWorkflowExample

    class IncomingIssues < Dynflow::Action

      def plan(issues)
        issues.each do |issue|
          plan_action(IncomingIssue, issue)
        end
        plan_self('issues' => issues)
      end

      input_format do
        param :issues, Array do
          param :author, String
          param :text, String
        end
      end

      def finalize
        TestExecutionLog.finalize << self
      end

      def summary
        # TODO fix, not a good pattern, it should delegate to IncomingIssue first
        triages   = all_planned_actions(Triage)
        assignees = triages.map do |triage|
          triage.output[:classification] &&
            triage.output[:classification][:assignee]
        end.compact.uniq
        { assignees: assignees }
      end
    end

    class IncomingIssue < Dynflow::Action

      def plan(issue)
        raise "You want me to fail" if issue == :fail
        plan_self(issue)
        plan_action(Triage, issue)
      end

      input_format do
        param :author, String
        param :text, String
      end

    end

    class Triage < Dynflow::Action

      def plan(issue)
        triage = plan_self(issue)
        plan_action(UpdateIssue,
                    author:   triage.input[:author],
                    text:     triage.input[:text],
                    assignee: triage.output[:classification][:assignee],
                    severity: triage.output[:classification][:severity])
      end

      input_format do
        param :author, String
        param :text, String
      end

      output_format do
        param :classification, Hash do
          param :assignee, String
          param :severity, %w[low medium high]
        end
      end

      def run
        TestExecutionLog.run << self
        TestPause.pause if input[:text].include? 'get a break'
        error! 'Trolling detected' if input[:text] == "trolling"
        self.output[:classification] = { assignee: 'John Doe', severity: 'medium' }
      end

      def finalize
        error! 'Trolling detected' if input[:text] == "trolling in finalize"
        TestExecutionLog.finalize << self
      end

    end

    class UpdateIssue < Dynflow::Action

      input_format do
        param :author, String
        param :text, String
        param :assignee, String
        param :severity, %w[low medium high]
      end

      def run
      end
    end

    class NotifyAssignee < Dynflow::Action

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

      def finalize
        TestExecutionLog.finalize << self
      end
    end

    class Commit < Dynflow::Action
      input_format do
        param :sha, String
      end

      def plan(commit, reviews = { 'Morfeus' => true, 'Neo' => true })
        sequence do
          ci, review_actions = concurrence do
            [plan_action(Ci, :commit => commit),
             reviews.map do |name, result|
               plan_action(Review, commit, name, result)
             end]
          end

          plan_action(Merge,
                      commit:         commit,
                      ci_result:      ci.output[:passed],
                      review_results: review_actions.map { |ra| ra.output[:passed] })
        end
      end
    end

    class FastCommit < Dynflow::Action

      def plan(commit)
        sequence do
          ci, review = concurrence do
            [plan_action(Ci, commit: commit),
             plan_action(Review, commit, 'Morfeus', true)]
          end

          plan_action(Merge,
                      commit:         commit,
                      ci_result:      ci.output[:passed],
                      review_results: [review.output[:passed]])
        end
      end

      input_format do
        param :sha, String
      end

    end

    class Ci < Dynflow::Action

      input_format do
        param :commit, Commit.input_format
      end

      output_format do
        param :passed, :boolean
      end

      def run
        output.update passed: true
      end
    end

    class Review < Dynflow::Action

      input_format do
        param :reviewer, String
        param :commit, Commit.input_format
      end

      output_format do
        param :passed, :boolean
      end

      def plan(commit, reviewer, result = true)
        plan_self commit: commit, reviewer: reviewer, result: result
      end

      def run
        output.update passed: input[:result]
      end
    end

    class Merge < Dynflow::Action

      input_format do
        param :commit, Commit.input_format
        param :ci_result, Ci.output_format
        param :review_results, array_of(Review.output_format)
      end

      def run
        output.update passed: (input.fetch(:ci_result) && input.fetch(:review_results).all?)
      end
    end

    class Dummy < Dynflow::Action
    end

    class DummyWithFinalize < Dynflow::Action
      def finalize
        TestExecutionLog.finalize << self
      end
    end

    class DummyTrigger < Dynflow::Action
    end

    class DummyAnotherTrigger < Dynflow::Action
    end

    class DummySubscribe < Dynflow::Action

      def self.subscribe
        DummyTrigger
      end

      def run
      end

    end

    class DummyMultiSubscribe < Dynflow::Action

      def self.subscribe
        [DummyTrigger, DummyAnotherTrigger]
      end

      def run
      end

    end

    class CancelableSuspended < Dynflow::Action
      include Dynflow::Action::Polling
      include Dynflow::Action::Cancellable

      Cancel = Dynflow::Action::Cancellable::Cancel

      def invoke_external_task
        { progress: 0 }
      end

      def poll_external_task
        progress     = external_task.fetch(:progress)
        new_progress = if progress == 30
                         if input[:text] =~ /cancel-external/
                           progress
                         elsif input[:text] =~ /cancel-self/
                           world.event execution_plan_id, run_step_id, Cancel
                           progress
                         else
                           progress + 10
                         end
                       else
                         progress + 10
                       end
        { progress: new_progress }
      end

      def cancel!
        if input[:text] !~ /cancel-fail/
          self.external_task = external_task.merge(cancelled: true)
        else
          error! 'action cancelled'
        end
      end

      def done?
        external_task && external_task[:progress] >= 100
      end

      def poll_interval
        0.01
      end

      def run_progress
        external_task && external_task[:progress].to_f / 100
      end
    end

  end
end
