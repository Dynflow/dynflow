module Dynflow
  module LoggerAdapters
    class Abstract

      # @returns [#fatal, #error, #warn, #info, #debug] logger object for logging errors from action execution
      def action_logger
        raise NotImplementedError
      end

      # @returns [#fatal, #error, #warn, #info, #debug] logger object for logging Dynflow errors
      def dynflow_logger
        raise NotImplementedError
      end

      def level
        raise NotImplementedError
      end

      def level=(v)
        raise NotImplementedError
      end

      private

      def apply_formatters(base, formatters)
        formatters.reduce(base) { |base, formatter| formatter.new(base) }
      end
    end
  end
end
