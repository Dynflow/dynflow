# frozen_string_literal: true

module Dynflow
  class Middleware
    require 'dynflow/middleware/register'
    require 'dynflow/middleware/world'
    require 'dynflow/middleware/resolver'
    require 'dynflow/middleware/stack'
    require 'dynflow/middleware/common/transaction'
    require 'dynflow/middleware/common/singleton'

    include Algebrick::TypeCheck

    def initialize(stack)
      @stack = Type! stack, Stack
    end

    # call `pass` to get deeper with the call
    def pass(*args, **kwargs)
      @stack.pass(*args, **kwargs)
    end

    # to get the action object
    def action
      @stack.action or raise "the action is not available"
    end

    def delay(*args, **kwargs)
      pass(*args, **kwargs)
    end

    def run(*args, **kwargs)
      pass(*args, **kwargs)
    end

    def plan(*args, **kwargs)
      pass(*args, **kwargs)
    end

    def finalize(*args, **kwargs)
      pass(*args, **kwargs)
    end

    def plan_phase(*args, **kwargs)
      pass(*args, **kwargs)
    end

    def finalize_phase(*args, **kwargs)
      pass(*args, **kwargs)
    end

    def present
      pass
    end

    def hook(*args, **kwargs)
      pass(*args, **kwargs)
    end
  end
end
