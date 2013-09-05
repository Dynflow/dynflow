module Dynflow
  module PersistenceAdapters
    class Abstract
      def load_execution_plan(execution_plan_id)
        raise NotImplementedError
      end

      def pagination?
        false
      end

      def find_execution_plans(options = {})
        raise NotImplementedError
      end

      def save_execution_plan(execution_plan_id, value)
        raise NotImplementedError
      end

      def load_action(execution_plan_id, action_id)
        raise NotImplementedError
      end

      def save_action(execution_plan_id, action_id, value)
        raise NotImplementedError
      end
    end
  end
end
