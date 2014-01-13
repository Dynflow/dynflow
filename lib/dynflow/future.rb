module Dynflow
  class Future
    Error            = Class.new StandardError
    FutureAlreadySet = Class.new Error
    FutureFailed     = Class.new Error
    TimeOut          = Class.new Error

    # `#future` will become resolved to `true` when ``#countdown!`` is called `count` times
    class CountDownLatch
      attr_reader :future

      def initialize(count, future = Future.new)
        raise ArgumentError if count < 0
        @count  = count
        @lock   = Mutex.new
        @future = future
      end

      def countdown!
        @lock.synchronize do
          @count -= 1 if @count > 0
          @future.resolve true if @count == 0 && !@future.ready?
        end
      end

      def count
        @lock.synchronize { @count }
      end
    end

    include Algebrick::TypeCheck
    extend Algebrick::TypeCheck

    def self.join(futures, result = Future.new)
      countdown = CountDownLatch.new(futures.size, result)
      futures.each do |future|
        Type! future, Future
        future.do_then { |_| countdown.countdown! }
      end
      result
    end

    def initialize(&task)
      @lock     = Mutex.new
      @value    = nil
      @resolved = false
      @failed   = false
      @waiting  = []
      @tasks    = []
      do_then &task if task
    end

    def value(timeout = nil)
      wait timeout
      @lock.synchronize { @value }
    end

    def value!
      value.tap { raise value if failed? }
    end

    def resolve(result)
      set result, false
    end

    def fail(exception)
      Type! exception, Exception, String
      if exception.is_a? String
        exception = FutureFailed.new(exception).tap { |e| e.set_backtrace caller }
      end
      set exception, true
    end

    def evaluate_to(&block)
      resolve block.call
    rescue => error
      self.fail error
    end

    def evaluate_to!(&block)
      evaluate_to &block
      raise value if self.failed?
    end

    def do_then(&task)
      call_task = @lock.synchronize do
        @tasks << task unless _ready?
        @resolved
      end
      task.call value if call_task
      self
    end

    def set(value, failed)
      @lock.synchronize do
        raise FutureAlreadySet, "future already set to #{@value} cannot use #{value}" if _ready?
        if failed
          @failed = true
        else
          @resolved = true
        end
        @value = value
        while (thread = @waiting.pop)
          begin
            thread.wakeup
          rescue ThreadError
            retry
          end
        end
        !failed
      end
      @tasks.each { |t| t.call value }
      self
    end

    def wait(timeout = nil)
      @lock.synchronize do
        unless _ready?
          @waiting << Thread.current
          clock.ping self, timeout, Thread.current, :expired if timeout
          @lock.sleep
          raise TimeOut unless _ready?
        end
      end
      self
    end

    def ready?
      @lock.synchronize { _ready? }
    end

    def resolved?
      @lock.synchronize { @resolved }
    end

    def failed?
      @lock.synchronize { @failed }
    end

    def tangle(future)
      do_then { |v| future.set v, failed? }
    end

    # @api private
    def expired(thread)
      @lock.synchronize do
        thread.wakeup if @waiting.delete(thread)
      end
    end

    private

    def _ready?
      @resolved || @failed
    end

    @clock_barrier = Mutex.new

    # @api private
    def self.clock
      @clock_barrier.synchronize do
        # TODO remove global state and use world.clock, needs to be terminated in right order
        @clock ||= Clock.new(::Logger.new($stderr)).tap do |clock|
          at_exit { clock.ask(Clock::Terminate).wait }
        end
      end
    end

    def clock
      self.class.clock
    end
  end
end
