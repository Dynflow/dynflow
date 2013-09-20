module Dynflow
  module Executors
    class Parallel < Abstract
      # TODO use actress when released, copied over from actress gem https://github.com/pitr-ch/actress
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
          on_message @mailbox.pop
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
