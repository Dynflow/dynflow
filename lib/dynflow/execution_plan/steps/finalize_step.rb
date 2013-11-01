module Dynflow
  module ExecutionPlan::Steps
    class FinalizeStep < AbstractFlowStep

      def self.state_transitions
        @state_transitions ||= super.clone.
            merge(pending:   [:skipped], # when its run_step is skipped
                  running:   [],
                  success:   [:pending], # when restarting finalize phase
                  suspended: [],
                  skipped:   [],
                  error:     [:pending] # when restarting finalize phase
        ) { |key, old, new| old + new}
      end


      def phase
        :finalize_phase
      end

    end
  end
end
