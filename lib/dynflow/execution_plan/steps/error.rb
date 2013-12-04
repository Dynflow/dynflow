module Dynflow
  module ExecutionPlan::Steps
    class Error < Serializable

      attr_reader :exception_class, :message, :backtrace

      def initialize(exception_class, message, backtrace)
        @exception_class = exception_class
        @message         = message
        @backtrace       = backtrace
      end

      def self.new_from_hash(hash)
        self.new(hash[:exception_class], hash[:message], hash[:backtrace])
      end

      def to_hash
        { class:           self.class.name,
          exception_class: exception_class,
          message:         message,
          backtrace:       backtrace }
      end

    end
  end
end
