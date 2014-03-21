module Dynflow
  module ExecutionPlan::Steps
    class AbstractFlowStep < Abstract

      def execute(*args)
        return self if [:skipped, :success].include? self.state
        open_action do |action|
          with_meta_calculation(action) do
            action.execute(*args)
          end
        end
      end

      def clone
        self.class.from_hash(to_hash, execution_plan_id, world)
      end

      private

      def open_action
        action = persistence.load_action(self)
        yield action
        persistence.save_action(execution_plan_id, action)
        save

        return self
      end
    end
  end
end
