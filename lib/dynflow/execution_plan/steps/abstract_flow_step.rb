module Dynflow
  module ExecutionPlan::Steps
    class AbstractFlowStep < Abstract

      def execute(*args)
        open_action do |action|
          action.indifferent_access_hash_variable_set :input, dereference(action.input)
          with_time_calculation do
            action.execute(*args)
          end
        end
      end

      def clone
        self.class.from_hash(to_hash, execution_plan_id, world)
      end


      def progress
        action = persistence.load_action(self)
        [action.progress_done, action.progress_weight]
      end

      private

      def open_action
        return self if [:skipped, :success].include? self.state
        action = persistence.load_action(self)

        yield action

        self.state = action.state
        self.error = action.error
        persistence.save_action(self, action)
        save

        return self
      end

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
