module Dynflow
  module CoordinatorAdapters
    class Sequel < Abstract
      def initialize(world)
        super
        @sequel_adapter = world.persistence.adapter
        Type! @sequel_adapter, PersistenceAdapters::Sequel
      end

      def acquire(lock)
        begin
          @sequel_adapter.save_lock(lock.to_hash)
        rescue ::Sequel::UniqueConstraintViolation
          raise Errors::LockError.new(lock)
        end
      end

      def release(lock)
        @sequel_adapter.delete_lock(lock.class.name, lock.id)
      end

      def find_locks(filter_options)
        @sequel_adapter.find_locks(filters: filter_options)
      end

    end
  end
end
