module Dynflow
  module ExecutionPlan::Steps
    class RunStep < Abstract

      def phase
        :run_phase
      end

      def execute
        action = persistence.load_step_action(self)
        action.execute

        self.state = action.state
        persistence.save_step_action(self, action)
        return self
      end
    end
  end
end
