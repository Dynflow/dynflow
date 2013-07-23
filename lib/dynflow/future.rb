module Dynflow
  # FIXME copied over from actress gem https://github.com/pitr-ch/actress
  class Future
    class FutureHappen < StandardError
    end

    def initialize
      @queue           = Queue.new
      @value           = nil
      @ready           = false
      @write_semaphore = Mutex.new
      @read_semaphore  = Mutex.new
    end

    def ready?
      @ready
    end

    def set(result)
      @write_semaphore.synchronize do
        raise FutureHappen, 'future already happen, cannot set again' if ready?
        @queue << result
        @ready = true
        self
      end
    end

    def value
      @read_semaphore.synchronize { @value ||= @queue.pop }
    end

    def wait
      value
      self
    end
  end
end
