module Dynflow
  module LoggerAdapters
    module Formatters
      class Exception < Abstract
        def format(message)
          if ::Exception === message
            "#{message.message} (#{message.class})\n#{message.backtrace.join("\n")}"
          else
            message
          end
        end
      end
    end
  end
end
