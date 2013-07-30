module Dynflow
  module ExecutionPlan::Steps
    class FinalizeStep < AbstractFlowStep

      def phase
        :finalize_phase
      end

    end
  end
end
