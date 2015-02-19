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

      def find_locks(filter_options)
        raise NotImplementedError
      end
    end
  end
end
