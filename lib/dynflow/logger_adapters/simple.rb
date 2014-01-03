require 'English'

module Dynflow
  module LoggerAdapters
    class Simple < Abstract
      require 'logger'

      attr_reader :logger, :action_logger, :dynflow_logger

      def initialize(output = $stdout, level = Logger::DEBUG, formatters = [Formatters::Exception])
        @logger           = Logger.new(output)
        @logger.level     = level
        @logger.formatter = method(:formatter).to_proc
        @action_logger    = apply_formatters ProgNameWrapper.new(@logger, ' action'), formatters
        @dynflow_logger   = apply_formatters ProgNameWrapper.new(@logger, 'dynflow'), formatters
      end

      private

      def formatter(severity, datetime, prog_name, msg)
        format "[%s #%d] %5s -- %s%s\n",
               datetime.strftime('%Y-%m-%d %H:%M:%S.%L'),
               $PID,
               severity,
               (prog_name ? prog_name + ': ' : ''),
               msg.to_s
      end

      class ProgNameWrapper
        def initialize(logger, prog_name)
          @logger    = logger
          @prog_name = prog_name
        end

        { fatal: 4, error: 3, warn: 2, info: 1, debug: 0 }.each do |method, level|
          define_method method do |message, &block|
            @logger.add level, message, @prog_name, &block
          end
        end
      end
    end
  end
end
