module Dynflow
  # TODO use actress when released, copied over from actress gem https://github.com/pitr-ch/actress
  class MicroActor
    include Algebrick::TypeCheck
    include Algebrick::Matching

    attr_reader :logger, :initialized, :terminated

    Terminate = Algebrick.atom

    def initialize(logger, *args)
      @logger      = logger
      @initialized = Future.new
      @thread      = Thread.new { run *args }
      Thread.pass until @terminated && @mailbox
    end

    def <<(message)
      @mailbox << [message, nil]
      self
    end

    def ask(message, future = Future.new)
      @mailbox << [message, future]
      future
    end

    def terminate!
      @initialized.wait
      return true if stopped?
      raise if Thread.current == @thread
      @mailbox << Terminate
      @terminated.value
    end

    def stopped?
      @terminated.ready?
    end

    private

    def delayed_initialize(*args)
    end

    def termination
    end

    def on_message(message)
      raise NotImplementedError
    end

    def receive
      message, future = @mailbox.pop
      #logger.debug "#{self.class} received:\n  #{message}"
      if message == Terminate
        termination
        throw Terminate
      end
      result = on_message message
      future.resolve result if future
    rescue => error
      logger.fatal error
    end

    def run(*args)
      Thread.current.abort_on_exception = true

      @mailbox    = Queue.new
      @terminated = Future.new

      delayed_initialize(*args)
      Thread.pass until @initialized
      @initialized.resolve true

      catch(Terminate) { loop { receive } }
      @terminated.resolve true
    end
  end
end
