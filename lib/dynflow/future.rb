module Dynflow
  # TODO use actress when released, copied over from actress gem https://github.com/pitr-ch/actress
  # TODO check that all Futures are resolved at some point, socket disconnecting

  class FutureAlreadySet < StandardError
  end

  class Future
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
      call_tasks = @lock.synchronize do
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
      @tasks.each { |t| t.call value } if call_tasks
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

    private

    def _ready?
      @resolved || @failed
    end
  end
end
