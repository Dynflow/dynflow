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
      Thread.current[:dynflow_middleware][:action]
    end

  end
end
