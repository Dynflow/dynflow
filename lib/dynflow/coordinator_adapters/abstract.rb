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

      def create_record(record)
        raise NotImplementedError
      end

      def delete_record(record)
        raise NotImplementedError
      end

      def find_records(record)
        raise NotImplementedError
      end
    end
  end
end
