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

      def release_by_owner(owner_id)
        @sequel_adapter.find_locks(filters: {owner_id: owner_id}).map do |lock_info|
          @sequel_adapter.delete_lock(lock_info[:class], lock_info[:id])
        end
      end

      def find_locks(filter_options)
        @sequel_adapter.find_locks(filters: filter_options)
      end

    end
  end
end
