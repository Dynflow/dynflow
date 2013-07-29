require 'sqlite3'
require 'active_record'
require 'multi_json'

module Dynflow
  module PersistenceAdapters
    class ActiveRecord < Abstract
      include Algebrick::TypeCheck

      class ExecutionPlan < ::ActiveRecord::Base
        self.table_name = 'dynflow_execution_plans'
      end

      class Action < ::ActiveRecord::Base
        self.table_name = 'dynflow_actions'
      end

      def find_execution_plans
        ExecutionPlan.all.map do |record|
          HashWithIndifferentAccess.new(MultiJson.load(record.data))
        end
      end

      def load_execution_plan(execution_plan_id)
        load ExecutionPlan, execution_plan_id
      end

      def save_execution_plan(execution_plan_id, value)
        save ExecutionPlan, execution_plan_id, value
      end

      def load_action(execution_plan_id, action_id)
        load Action, execution_plan_id + action_id
      end

      def save_action(execution_plan_id, action_id, value)
        save Action, execution_plan_id + action_id, value
      end

      private

      def save(klass, id, value)
        existing_record = klass.where(identification: id).first
        if value
          record      = existing_record || klass.new(identification: id)
          is_kind_of! value, Hash
          record.data = MultiJson.dump value
          record.save!
        else
          existing_record and existing_record.destroy
        end
        value
      end

      def load(klass, id)
        if (record = klass.where(identification: id).first)
          HashWithIndifferentAccess.new MultiJson.load(record.data)
        else
          raise KeyError
        end
      end
    end
  end
end
