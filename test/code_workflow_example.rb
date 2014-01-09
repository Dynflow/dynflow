require 'logger'

module Dynflow
  module CodeWorkflowExample

    class IncomingIssues < Action

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
        triages   = all_actions.find_all do |action|
          action.is_a? Dynflow::CodeWorkflowExample::Triage
        end
        assignees = triages.map do |triage|
          triage.output[:classification] &&
              triage.output[:classification][:assignee]
        end.compact.uniq
        { assignees: assignees }
      end

    end

    class Slow < Action
      def plan(seconds)
        plan_self interval: seconds
      end

      def run
        sleep input[:interval]
        action_logger.debug 'done with sleeping'
        $slow_actions_done ||= 0
        $slow_actions_done +=1
      end
    end

    class IncomingIssue < Action

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

    class UpdateIssue < Action

      input_format do
        param :author, String
        param :text, String
        param :assignee, String
        param :severity, %w[low medium high]
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

      def finalize
        TestExecutionLog.finalize << self
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

    class Dummy < Action
    end

    class DummyWithFinalize < Action
      def finalize
        TestExecutionLog.finalize << self
      end
    end

    class DummyTrigger < Action
    end

    class DummyAnotherTrigger < Action
    end

    class DummySubscribe < Action

      def self.subscribe
        DummyTrigger
      end

      def run
      end

    end

    class DummyMultiSubscribe < Action

      def self.subscribe
        [DummyTrigger, DummyAnotherTrigger]
      end

      def run
      end

    end

    class DummySuspended < Action

      include Action::Polling

      def invoke_external_task
        error! 'Trolling detected' if input[:text] == 'troll setup'
        { progress: 0, done: false }
      end

      def external_task=(external_task_data)
        self.output.update external_task_data
      end

      def external_task
        output
      end

      def poll_external_task
        if input[:text] == 'troll progress' && !output[:trolled]
          output[:trolled] = true
          error! 'Trolling detected'
        end

        if input[:text] =~ /pause in progress (\d+)/
          TestPause.pause if output[:progress] == $1.to_i
        end

        progress = output[:progress] + 10
        { progress: progress, done: progress >= 100 }
      end

      def done?
        external_task[:progress] >= 100
      end

      def poll_interval
        0.001
      end

      def run_progress
        output[:progress].to_f / 100
      end
    end

    class DummyHeavyProgress < Action

      def plan(input)
        sequence do
          plan_self(input)
          plan_action(DummySuspended, input)
        end
      end

      def run
      end

      def finalize
      end

      def run_progress_weight
        4
      end

      def finalize_progress_weight
        5
      end
    end

  end
end
