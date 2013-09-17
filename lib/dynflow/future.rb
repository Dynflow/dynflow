module Dynflow
  # TODO copied over from actress gem https://github.com/pitr-ch/actress
  class Future
    class FutureHappen < StandardError
    end

    def initialize
      @lock    = Mutex.new
      @value   = nil
      @waiting = []
    end

    def value
      wait
      @lock.synchronize { @value }
    end

    def set(result)
      @lock.synchronize do
        raise FutureHappen, 'future already happen, cannot set again' if _ready?
        @value = result
        @waiting.each do |t|
          begin
            t.wakeup
          rescue ThreadError
            retry
          end
        end
      end
    end

    def wait
      @lock.synchronize do
        @waiting << Thread.current
        @lock.sleep unless _ready?
      end
    end

    def ready?
      @lock.synchronize { _ready? }
    end

    private

    def _ready?
      !!@value
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
