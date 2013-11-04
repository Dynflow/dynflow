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
            error:     [:pending] # when restarting finalize phase
        }
      end


      def phase
        :finalize_phase
      end

    end
  end
end
