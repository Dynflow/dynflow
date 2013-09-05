module Dynflow
  module PersistenceAdapters
    class Memory < Abstract
      include Algebrick::TypeCheck

      def initialize
        @execution_plans = {}
        @actions         = {}
      end

      def pagination?
        true
      end

      def find_execution_plans(options = {})
        values = @execution_plans.values
        values = paginate(values, options[:page], options[:per_page])
        values.map(&:with_indifferent_access)
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

      private

      def paginate(values, page, per_page)
        return values unless page && per_page
        start_index = page * per_page
        end_index   = start_index + per_page
        start_index = [0, [start_index, values.size].min].max
        end_index   = [0, [end_index, values.size].min].max
        values[start_index...end_index]
      end
    end
  end

end
