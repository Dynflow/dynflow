module Dynflow
  module CoordinatorAdapters
    class Abstract
      include Algebrick::TypeCheck

      def initialize(world)
        Type! world, World
        @world = world
      end

      def acquire(lock)
        raise NotImplementedError
      end

      def release(lock)
        raise NotImplementedError
      end

      # release all locks acquired by some world: needed for world
      # invalidation: we don't want for it to hold the locks forever
      def release_by_owner(owner_id)
        raise NotImplementedError
      end

      def find_locks(filter_options)
        raise NotImplementedError
      end
    end
  end
end
