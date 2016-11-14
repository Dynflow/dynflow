module Dynflow
  module ExecutionPlan::Steps
    class RunStep < AbstractFlowStep

      def self.state_transitions
        @state_transitions ||= {
            pending:   [:running, :skipped, :error], # :skipped when it cannot be run because it depends on skipping step
            running:   [:success, :error, :suspended],
            success:   [:suspended], # after not-done process_update
            suspended: [:running, :error], # process_update, e.g. error in setup_progress_updates
            skipping:  [:error, :skipped], # waiting for the skip method to be called
            skipped:   [],
            error:     [:skipping, :running]
        }
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
  end
end
