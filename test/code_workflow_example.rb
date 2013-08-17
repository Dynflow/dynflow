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
        raise 'Trolling detected' if input[:text].include? "trolling"
        self.output[:classification] = { assignee: 'John Doe', severity: 'medium' }
      end

      def finalize
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

    class PollingServiceImpl < Dynflow::Executors::Parallel::MicroActor

      Task = Algebrick::Product.new(action:           Action::Suspended,
                                    external_task_id: String)
      Tick = Algebrick::Atom.new

      def initialize
        super
        @tasks = Set.new
        @clocks = Thread.new { loop { tick } }
        @pending_tick = false
        @progress = Hash.new { |h, k| h[k] = 0 }
      end

      def wait_for_task(action, external_task_id)
        # simulate polling for the state of the external task
        self << Task[action,
                     external_task_id]
      end

      private

      def interval
        0.1
      end

      def on_message(message)
        match(message,
              ~Task.to_m >>-> task do
                @tasks << task
              end,
              Tick >>-> do
                @pending_tick = false
                poll
              end)
      end

      def tick
        unless @pending_tick
          @pending_tick = true
          self << Tick
        end
        sleep interval
      end

      def poll
        @tasks.delete_if do |task|
          key = "#{task[:action].execution_plan_id}-#{task[:action].step_id}"
          @progress[key] += 10

          progress = @progress[key]
          if progress == 100
            task[:action].resume(:done, progress: 100)
            true
          elsif progress % 10 == 0
            task[:action].resume(:update_progress, progress: progress)
            true
          else
            false
          end
        end
      end

    end

    PollingService = PollingServiceImpl.new

    class DummySuspended < Action

      def run
        PollingService.wait_for_task(suspend, input[:external_task_id])
      end

      # called when there is some update about the progress of the task
      def update_progress(data)
        self.output = { progress: data[:progress] }
        puts "------------- update_progress"
        pp output
        PollingService.wait_for_task(suspend, input[:external_task_id])
      end

      # called when the task is finished outside
      def done(data)
        puts "------------- done"
        self.output[:progress] = 100
        pp output
      end

    end

  end
end
