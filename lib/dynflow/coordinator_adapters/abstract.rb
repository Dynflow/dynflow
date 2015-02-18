module Dynflow
  module CoordinatorAdapters
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
