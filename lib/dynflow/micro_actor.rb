module Dynflow
  # TODO use actress when released, copied over from actress gem https://github.com/pitr-ch/actress
  class MicroActor
    include Algebrick::TypeCheck
    include Algebrick::Matching

    attr_reader :logger

    def initialize(logger)
      @mailbox                   = Queue.new
      @thread                    = Thread.new { loop { receive } }
      @thread.abort_on_exception = true
      @logger                    = logger
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

  class MicroActorWithFutures < MicroActor
    def <<(message, future = Future.new)
      @mailbox << [message, future]
      future
    end

    def receive
      message, future = @mailbox.pop
      future.set on_message(message)
    rescue => error
      logger.fatal error
      future.set error
    end
  end
end
