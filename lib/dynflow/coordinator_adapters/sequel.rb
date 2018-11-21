module Dynflow
  module CoordinatorAdapters
    class Sequel < Abstract
      def initialize(world)
        super
        @sequel_adapter = world.persistence.adapter
        Type! @sequel_adapter, PersistenceAdapters::Sequel
      end

      def create_record(record)
        @sequel_adapter.insert_coordinator_record(record.to_hash)
      rescue Errors::PersistenceError => e
        if e.cause.is_a? ::Sequel::UniqueConstraintViolation
          raise Coordinator::DuplicateRecordError.new(record)
        else
          raise e
        end
      end

      def update_record(record)
        @sequel_adapter.update_coordinator_record(record.class.name, record.id, record.to_hash)
      end

      def delete_record(record)
        @sequel_adapter.delete_coordinator_record(record.class.name, record.id)
      end

      def find_records(filter_options)
        @sequel_adapter.find_coordinator_records(filters: filter_options)
      end

      def find_execution_plans(filter_options)
        @sequel_adapter.find_execution_plans(filters: filter_options)
      end
    end
  end
end
