module Dynflow
  module ExecutionPlan::Steps
    class FinalizeStep < AbstractFlowStep

      def self.state_transitions
        @state_transitions ||= {
            pending:   [:running, :skipped], # :skipped when its run_step is skipped
            running:   [:success, :error],
            success:   [:pending], # when restarting finalize phase
            suspended: [],
            skipped:   [],
            error:     [:pending, :skipped] # pending when restarting finalize phase
        }
      end

      def update_from_action(action)
        super
        self.progress_weight = action.finalize_progress_weight
      end

      def phase
        Action::Finalize
      end

      def mark_to_skip
        self.state = :skipped
        self.save
      end

    end
  end
end
