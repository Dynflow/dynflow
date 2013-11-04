module Dynflow
  module ExecutionPlan::Steps
    class RunStep < AbstractFlowStep

      def self.state_transitions
        @state_transitions ||= {
            pending:   [:running, :skipped], # :skipped when it cannot be run because it depends on skipped step
            running:   [:success, :error, :suspended],
            success:   [:suspended], # after not-done process_update
            suspended: [:running], # process_update
            skipped:   [],
            error:     [:skipped, :running]
        }
      end

      def phase
        :run_phase
      end
    end
  end
end
