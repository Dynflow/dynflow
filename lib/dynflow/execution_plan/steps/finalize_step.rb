module Dynflow
  module ExecutionPlan::Steps
    class FinalizeStep < Abstract

      def phase
        :finalize_phase
      end

    end
  end
end
