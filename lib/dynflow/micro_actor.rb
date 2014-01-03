module Dynflow
  class MicroActor
    include Algebrick::TypeCheck
    include Algebrick::Matching

    attr_reader :logger, :initialized

    Terminate = Algebrick.atom

    def initialize(logger, *args)
      @logger      = logger
      @initialized = Future.new
      @thread      = Thread.new { run *args }
      Thread.pass until @mailbox
    end

    def <<(message)
      raise 'actor terminated' if terminated?
      @mailbox << [message, nil]
      self
    end

    def ask(message, future = Future.new)
      @mailbox << [message, future]
      future
    end

    def stopped?
      @terminated.ready?
    end

    private

    def delayed_initialize(*args)
    end

    def termination
      terminate!
    end

    def terminating?
      @terminated
    end

    def terminated?
      terminating? && @terminated.ready?
    end

    def terminate!
      raise unless Thread.current == @thread
      @terminated.resolve true
    end

    def on_message(message)
      raise NotImplementedError
    end

    def receive
      message, future = @mailbox.pop
      #logger.debug "#{self.class} received:\n  #{message}"
      if message == Terminate
        if terminating?
          @terminated.do_then { future.resolve true } if future
        else
          @terminated = (future || Future.new).do_then { throw Terminate }
          termination
        end
      else
        result = on_message message
        future.resolve result if future
      end
    rescue => error
      logger.fatal error
    end

    def run(*args)
      Thread.current.abort_on_exception = true

      @mailbox    = Queue.new
      @terminated = nil

      delayed_initialize(*args)
      Thread.pass until @initialized
      @initialized.resolve true

      catch(Terminate) { loop { receive } }
    end
  end
end
