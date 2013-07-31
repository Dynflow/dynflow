module Dynflow
  module Executors
    class Parallel < Abstract
      class MicroActor
        include Algebrick::TypeCheck
        include Algebrick::Matching

        def initialize
          @mailbox = Queue.new
          @thread  = Thread.new { loop { receive } }
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
          # TODO log to a logger instead
          $stderr.puts "FATAL #{error.message} (#{error.class})\n#{error.backtrace.join("\n")}"
        end

      end
    end
  end
end
