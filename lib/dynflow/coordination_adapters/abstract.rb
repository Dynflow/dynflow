module Dynflow
  module CoordinationAdapters

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

    class Abstract
      include Algebrick::TypeCheck

      def initialize(world)
        Type! world, World
        @world = world
      end

      def lock(lock_request)
        raise NotImplementedError
      end

      def unlock(lock_request)
        raise NotImplementedError
      end

      # release all locks acquired by some world: needed for world
      # invalidation: we don't want for it to hold the locks forever
      def unlock_all(world_id)
        raise NotImplementedError
      end
    end
  end
end
