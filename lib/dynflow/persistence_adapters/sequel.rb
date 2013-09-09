require 'sequel'
require 'multi_json'

module Dynflow
  module PersistenceAdapters

    Sequel.extension :migration

    class Sequel < Abstract
      include Algebrick::TypeCheck

      attr_reader :db

      def initialize(db_path)
        @db = initialize_db db_path
        migrate_db
      end

      def find_execution_plans
        # TODO order
        execution_plans_table.map do |record|
          HashWithIndifferentAccess.new(MultiJson.load(record[:data]))
        end
      end

      def load_execution_plan(execution_plan_id)
        load execution_plans_table, uuid: execution_plan_id
      end

      def save_execution_plan(execution_plan_id, value)
        save execution_plans_table, { uuid: execution_plan_id }, value
      end

      def load_action(execution_plan_id, action_id)
        load actions_table, execution_plan_uuid: execution_plan_id, id: action_id
      end

      def save_action(execution_plan_id, action_id, value)
        save actions_table, { execution_plan_uuid: execution_plan_id, id: action_id }, value
      end

      private

      def execution_plans_table
        db[:dynflow_execution_plans]
      end

      def actions_table
        db[:dynflow_actions]
      end

      def initialize_db(db_path)
        ::Sequel.connect db_path
      end

      def self.migrations_path
        File.expand_path('../sequel_migrations', __FILE__)
      end

      def migrate_db
        ::Sequel::Migrator.apply(db, self.class.migrations_path)
      end

      def save(table, condition, value)
        existing_record = table.first condition
        if value
          record = existing_record || condition
          is_kind_of! value, Hash
          record[:data] = MultiJson.dump value
          table.insert record
        else
          existing_record and table.where(condition).delete
        end
        value
      end

      def load(table, condition)
        if (record = table.first(condition))
          HashWithIndifferentAccess.new MultiJson.load(record[:data])
        else
          raise KeyError
        end
      end
    end
  end
end
