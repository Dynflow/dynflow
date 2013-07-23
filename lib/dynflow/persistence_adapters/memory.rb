module Dynflow
  module PersistenceAdapters
    class Memory < Abstract
      include Algebrick::TypeCheck

      def initialize
        @execution_plans = {}
        @steps           = {}
      end

      def load_execution_plan(execution_plan_id)
        @execution_plans.fetch execution_plan_id
      end

      def save_execution_plan(execution_plan_id, value)
        is_kind_of! value, Hash
        if value.nil?
          @execution_plans.delete execution_plan_id
        else
          @execution_plans[execution_plan_id] = value
        end
      end

      def load_step(execution_plan_id, step_id)
        @steps.fetch [execution_plan_id, step_id]
      end

      def save_step(execution_plan_id, step_id, value)
        is_kind_of! value, Hash
        if value.nil?
          @steps.delete [execution_plan_id, step_id]
        else
          @steps[[execution_plan_id, step_id]] = value
        end
      end
    end
  end

end
