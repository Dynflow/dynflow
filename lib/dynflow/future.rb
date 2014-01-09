module Dynflow
  class FutureAlreadySet < StandardError
  end

  class FutureFailed < StandardError
  end

  class Future
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

    def value
      wait
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
      set block.call, false
    rescue => error
      set error, true
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

    def wait
      @lock.synchronize do
        unless _ready?
          @waiting << Thread.current
          @lock.sleep
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

    private

    def _ready?
      @resolved || @failed
    end
  end
end
