module Dynflow
  module ExecutionPlan::Steps
    class RunStep < AbstractFlowStep

      def phase
        :run_phase
      end

    end
  end
end
