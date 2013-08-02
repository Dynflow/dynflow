module Dynflow
  module ExecutionPlan::Steps
    class AbstractFlowStep < Abstract

      # TODO add and store start_time, end_time and run_time duration
      def execute
        action = persistence.load_action(self)
        action.input = dereference(action.input)
        action.execute

        self.state = action.state
        persistence.save_action(self, action)

        return self
      end

      def clone
        self.class.from_hash(to_hash, execution_plan_id, world)
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
