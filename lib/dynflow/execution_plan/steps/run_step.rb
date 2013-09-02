module Dynflow
  module ExecutionPlan::Steps
    class RunStep < AbstractFlowStep

      def phase
        :run_phase
      end

      def resume(method, *args)
        open_action do |action|
          action.__resume__(method, *args)
        end
      end

    end
  end
end
