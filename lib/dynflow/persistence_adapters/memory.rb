module Dynflow
  module PersistenceAdapters
    class Memory < Abstract
      include Algebrick::TypeCheck

      def initialize
        @execution_plans = {}
        @actions         = {}
      end

      def find_execution_plans
        @execution_plans.values.map(&:with_indifferent_access)
      end

      def load_execution_plan(execution_plan_id)
        @execution_plans.fetch(execution_plan_id).with_indifferent_access
      end

      def save_execution_plan(execution_plan_id, value)
        if value.nil?
          @execution_plans.delete execution_plan_id
        else
          is_kind_of! value, Hash
          @execution_plans[execution_plan_id] = value
        end
      end

      def load_action(execution_plan_id, action_id)
        @actions.fetch([execution_plan_id, action_id]).with_indifferent_access
      end

      def save_action(execution_plan_id, action_id, value)
        if value.nil?
          @actions.delete [execution_plan_id, action_id]
        else
          is_kind_of! value, Hash
          @actions[[execution_plan_id, action_id]] = value
        end
      end
    end
  end

end
