require 'dynflow/coordinator_adapters'

module Dynflow
  class Coordinator

    class LockRequest
      # Bare minimum to be implemented to aquire the lock.
      # The various adapters can use additional metadata that the
      # LockRequest ancestors might offer.
      def lock_id
        raise NotImplementedError
      end

      def to_s
        "#{self.class.name}: #{lock_id}"
      end
    end

    class WorldInvalidationLock < LockRequest
      attr_reader :invalidated_world
      def initialize(invalidated_world)
        @invalidated_world = invalidated_world
      end

      def lock_id
        "world-invalidation:#{@invalidated_world.id}"
      end
    end

    class ConsistencyCheckLock < LockRequest
      def lock_id
        "consistency-check"
      end
    end

    attr_reader :adapter

    def initialize(world, coordinator_adapter)
      @world   = world
      @adapter = coordinator_adapter
    end

    def lock(lock_request, &block)
      raise Errors::InactiveWorldError.new(@world) if @world.terminating?
      adapter.lock(lock_request)
      if block
        begin
          block.call
        ensure
          adapter.unlock(lock_request)
        end
      end
    end

    def unlock(lock_request)
      adapter.unlock(lock_request)
    end

    def unlock_all(world_id)
      adapter.unlock_all(world_id)
    end

  end
end
