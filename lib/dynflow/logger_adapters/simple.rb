require 'English'

module Dynflow
  module LoggerAdapters
    class Simple < Abstract
      require 'logger'

      attr_reader :action_logger, :dynflow_logger

      def initialize(output = $stdout)
        @logger           = Logger.new output
        @logger.formatter = method(:formatter).to_proc
        @action_logger    = ProgNameWrapper.new @logger, ' action'
        @dynflow_logger   = ProgNameWrapper.new @logger, 'dynflow'
      end

      private

      def formatter(severity, datetime, prog_name, msg)
        format "[%s #%d] %5s -- %s%s\n",
               datetime.strftime('%Y-%m-%d %H:%M:%S.%L'),
               $PID,
               severity,
               (prog_name ? prog_name + ': ' : ''),
               case msg
               when ::String
                 msg
               when ::Exception
                 "#{ msg.message } (#{ msg.class })\n" <<
                     (msg.backtrace || []).join("\n")
               else
                 msg.inspect
               end
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
