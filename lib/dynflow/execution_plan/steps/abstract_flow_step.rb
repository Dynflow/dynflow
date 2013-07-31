module Dynflow
  module ExecutionPlan::Steps
    class AbstractFlowStep < Abstract

      def execute
        action = persistence.load_action(self)
        action.input = dereference(action.input)
        action.execute

        self.state = action.state
        persistence.save_action(self, action)

        return self
      end

      private

      def dereference(input)
        case input
        when Hash
          input.reduce(HashWithIndifferentAccess.new) do |h, (key, val)|
            h.update(key => dereference(val))
          end
        when Array
          input.map { |val| dereference(val) }
        when ExecutionPlan::OutputReference
          input.dereference(persistence, execution_plan_id)
        else
          input
        end
      end
    end
  end
end
