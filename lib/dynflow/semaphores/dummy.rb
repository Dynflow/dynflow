module Dynflow
  module Semaphores
    class Dummy < Abstract

      def wait(thing)
        true
      end

      def get_waiting
        nil
      end

      def has_waiting?
        false
      end

      def release(*args)
      end

      def save
      end

      def get(n)
        n
      end

      def free
        1
      end
    end
  end
end
