module Dynflow
  module ExecutionPlan::Steps
    class AbstractFlowStep < Abstract

      def execute
        action = persistence.load_action(self)

        action.execute

        self.state = action.state
        persistence.save_action(self, action)

        return self
      end

    end
  end
end
