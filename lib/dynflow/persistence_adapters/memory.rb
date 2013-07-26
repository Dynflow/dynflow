module Dynflow
  module PersistenceAdapters
    class Memory < Abstract
      include Algebrick::TypeCheck

      def initialize
        @execution_plans = {}
        @actions         = {}
      end

      def supported_options_for_find
        [:result, :page, :per_page]
      end

      def check_find_options!(options)
        unsupported_options = options.keys - supported_options_for_find
        if unsupported_options.any?
          raise ArgumentError,
                "Unsupported options: #{unsupported_options.join(', ')}"
        end
      end

      def find_execution_plans(options)
        check_find_options!(options)
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
