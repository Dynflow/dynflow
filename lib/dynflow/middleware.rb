module Dynflow
  class Middleware
    require 'dynflow/middleware/action'
    require 'dynflow/middleware/resolver'
    require 'dynflow/middleware/stack'

    def initialize(stack)
      @stack = stack
    end

    # call `stack.pass` to get deeper with the call
    def stack
      @stack.rest
    end

    # to get the action object
    def action
      @stack.action or raise "the action is not available"
    end

  end
end
