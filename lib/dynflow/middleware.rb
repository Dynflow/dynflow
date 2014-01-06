module Dynflow
  class Middleware
    require 'dynflow/middleware/action'
    require 'dynflow/middleware/resolver'
    require 'dynflow/middleware/stack'

    # call `stack.pass` to get deeper with the call
    def stack
      Thread.current[:dynflow_middleware][:stack]
    end

    # to get the action object
    def action
      target = Thread.current[:dynflow_middleware][:target]
      if target.is_a? Proc
        raise "the action is not available"
      else
        target
      end
    end

  end
end
