module Dynflow
  # TODO use actress when released, copied over from actress gem https://github.com/pitr-ch/actress
  class Future
    class FutureHappen < StandardError
    end

    def initialize
      @lock     = Mutex.new
      @value    = nil
      @resolved = false
      @waiting  = []
    end

    def value
      wait
      @lock.synchronize { @value }
    end

    def set(result)
      @lock.synchronize do
        raise FutureHappen, 'future already happen, cannot set again' if _ready?
        @resolved = true
        @value    = result
        while (thread = @waiting.pop)
          begin
            thread.wakeup
          rescue ThreadError
            retry
          end
        end
      end
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

    private

    def _ready?
      @resolved
    end
  end

  class FutureTask < Future
    def initialize(&task)
      super()
      @task = task
    end

    def set(result)
      super result
      @task.call result
      self
    end
  end
end
