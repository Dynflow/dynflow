module Dynflow
  # TODO use actress when released, copied over from actress gem https://github.com/pitr-ch/actress
  class MicroActor
    include Algebrick::TypeCheck
    include Algebrick::Matching

    attr_reader :logger

    def initialize(logger, *args)
      @logger = logger
      @thread = Thread.new do
        Thread.current.abort_on_exception = true
        @mailbox                          = Queue.new
        @stop                             = false
        @stopped                          = Future.new
        delayed_initialize(*args)
        loop do
          break if @stop
          receive
        end
        @stop.set true
      end
      Thread.pass while @stopped.nil?
    end

    def <<(message)
      @mailbox << message
      self
    end

    def terminate!
      @stop = true
      @stopped.wait
    end

    private

    def delayed_initialize(*args)
    end

    def on_message(message)
      raise NotImplementedError
    end

    def receive
      on_message @mailbox.pop
    rescue => error
      logger.fatal error
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
