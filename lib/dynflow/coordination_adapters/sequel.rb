module Dynflow
  module CoordinationAdapters
    class Sequel < Abstract
      def initialize(world)
        super
        @sequel_adapter = world.persistence.adapter
        Type! @sequel_adapter, PersistenceAdapters::Sequel
      end

      def lock(lock_request)
        begin
          @sequel_adapter.create_lock(lock_request.lock_id, @world.id)
        rescue ::Sequel::UniqueConstraintViolation
          raise Errors::LockError.new(lock_request)
        end
      end

      def unlock(lock_request)
        @sequel_adapter.delete_lock(lock_request.lock_id)
      end

      def unlock_all(world_id)
        @sequel_adapter.find_locks(world_id: world_id).map do |lock_info|
          @sequel_adapter.delete_lock(lock_info[:id])
        end
      end
    end
  end
end
