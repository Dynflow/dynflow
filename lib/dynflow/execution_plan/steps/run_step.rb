module Dynflow
  module ExecutionPlan::Steps
    class RunStep < AbstractFlowStep

      def self.state_transitions
        @state_transitions ||= {
            pending:   [:running, :skipped, :error], # :skipped when it cannot be run because it depends on skipping step
            running:   [:success, :error, :suspended],
            success:   [:suspended, :reverted], # after not-done process_update
            suspended: [:running, :error], # process_update, e.g. error in setup_progress_updates
            skipping:  [:error, :skipped], # waiting for the skip method to be called
            skipped:   [],
            error:     [:skipping, :running, :reverted]
        }
      end

      def update_from_action(action)
        super
        self.progress_weight = action.run_progress_weight
      end

      def phase
        Action::Run
      end

      def cancellable?
        [:suspended, :running].include?(self.state) &&
          self.action_class < Action::Cancellable
      end

      def with_sub_plans?
        self.action_class < Action::WithSubPlans
      end

      def mark_to_skip
        case self.state
        when :error
          self.state = :skipping
        when :pending
          self.state = :skipped
        else
          raise "Skipping step in #{self.state} is not supported"
        end
        self.save
      end
    end

    class RevertRunStep < RunStep
      include Revert

      def real_execute(action, event)
        action.send(:in_run_phase, event) do |action, event|
          world.middleware.execute(:revert_run, action, *[event].compact) do |*new_args|
            action.revert_run(*new_args)
          end
        end
        reset_original_step!(action, 'run')
        original_execution_plan(action).update_state(:planned) if entry_action?(action)
      end

    end
  end
end
