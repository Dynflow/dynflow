module Dynflow
  class Future

    attr_accessor :ivar

    def initialize
      @ivar = Concurrent::IVar.new
    end

    def value(timeout = nil)
      @ivar.value timeout
    end

    def value!(timeout = nil)
      @ivar.value! timeout
    end

    def resolve(result)
      @ivar.set result
      self
    end

    def fail(exception)
      @ivar.fail exception
      self
    end

    def evaluate_to(&block)
      resolve block.call
    rescue => error
      self.fail error
    end

    def evaluate_to!(&block)
      evaluate_to &block
      raise reason if self.failed?
    end

    def do_then(&task)
      @ivar.with_observer { |_, _, v| task.call v }
      self
    end

    def set(value, failed)
      @ivar.complete failed, value, value
      self
    end

    def wait(timeout = nil)
      @ivar.wait timeout
      self
    end

    def ready?
      @ivar.completed?
    end

    def resolved?
      @ivar.fulfilled?
    end

    def failed?
      @ivar.rejected?
    end

    def tangle(future)
      do_then { |v| future.set v, failed? }
    end
  end
end
