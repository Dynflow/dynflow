module Dynflow
  module LoggerAdapters
    module Formatters
      class Exception < Abstract
        def format(message)
          if ::Exception === message
            backtrace = Actor::BacktraceCollector.full_backtrace(message.backtrace)
            "#{message.message} (#{message.class})\n#{backtrace.join("\n")}"
          else
            message
          end
        end
      end
    end
  end
end
