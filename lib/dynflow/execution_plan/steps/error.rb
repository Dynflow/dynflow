module Dynflow
  module ExecutionPlan::Steps
    class Error < Serializable

      attr_reader :exception, :message, :backtrace

      def initialize(exception_class, message, backtrace)
        @exception_class = exception_class
        @message         = message
        @backtrace       = backtrace
      end

      def self.new_from_hash(hash)
        self.new(hash[:exception], hash[:message], hash[:backtrace])
      end

      def to_hash
        { class:     self.class.name,
          exception: exception,
          message:   message,
          backtrace: backtrace }
      end

    end
  end
end
