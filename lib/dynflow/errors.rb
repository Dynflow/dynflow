module Dynflow
  module Errors
    class RescueError < StandardError; end

    # placeholder in case the deserialized error is no longer available
    class UnknownError < StandardError
      def self.for_exception_class(class_name)
        Class.new(self) do
          define_singleton_method :name do
            class_name
          end
        end
      end

      def self.inspect
        "#{UnknownError.name}[#{name}]"
      end

      def self.to_s
        inspect
      end

      def inspect
        "#{self.class.inspect}: #{message}"
      end
    end

    class PersistenceError < StandardError
      def self.delegate(original_exception)
        self.new("caused by #{original_exception.class}: #{original_exception.message}").tap do |e|
          e.set_backtrace original_exception.backtrace
        end
      end
    end

    class LockError < StandardError
      attr_reader :lock_request

      def initialize(lock_request)
        @lock_request = lock_request
        super("Unable to acquire lock #{lock_request}")
      end
    end
  end
end
