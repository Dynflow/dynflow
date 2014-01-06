module Dynflow
  class Middleware
    require 'dynflow/middleware/action'
    require 'dynflow/middleware/resolver'
    require 'dynflow/middleware/stack'

    # call `stack.pass` to get deeper with the call
    def stack
      Stack.thread_data[:stack]
    end

    # to get the action object
    def action
      target = Stack.thread_data[:target]
      if target.is_a? Proc
        raise "the action is not available"
      else
        target
      end
    end

  end
end
