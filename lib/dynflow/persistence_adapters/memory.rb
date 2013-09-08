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

      def ordering_by
        [:state]
      end

      def filtering_by
        [:state]
      end

      def find_execution_plans(options = {})
        values = filter(options[:filters])
        values = order(values, options[:order_by], options[:desc])
        values = paginate(values, options[:page], options[:per_page])
        return values
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

      def filter(filters)
        values = @execution_plans.values.map(&:with_indifferent_access)
        return values unless filters

        filters.each do |attr, attr_filters|
          attr_filters = Array(attr_filters)
          values = values.select do |value|
            attr_filters.any? { |expected| expected.to_s == value[attr].to_s }
          end
        end
        return values
      end

      def paginate(values, page, per_page)
        return values unless page && per_page
        start_index = page * per_page
        end_index   = start_index + per_page
        start_index = [0, [start_index, values.size].min].max
        end_index   = [0, [end_index, values.size].min].max
        values[start_index...end_index]
      end

      def order(values, order_by, desc)
        return values unless ordering_by.any? { |attr| attr.to_s == order_by.to_s }
        values = values.sort_by { |value| value[order_by] }
        if desc
          return values.reverse
        else
          return values
        end
      end
    end
  end

end
