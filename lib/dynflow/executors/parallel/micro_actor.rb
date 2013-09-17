module Dynflow
  module Executors
    class Parallel < Abstract
      class MicroActor
        include Algebrick::TypeCheck
        include Algebrick::Matching

        attr_reader :logger

        def initialize(logger)
          @mailbox = Queue.new
          @thread  = Thread.new { loop { receive } }
          @logger  = logger
        end

        def <<(message)
          @mailbox << message
        end

        private

        def on_message(message)
          raise NotImplementedError
        end

        def receive
          on_message @mailbox.pop #.tap { |m| puts "received: #{m}" }
        rescue => error
          logger.fatal error
        end

        def terminate!
          @thread.terminate
        end
      end
    end
  end
end
