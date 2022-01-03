# frozen_string_literal: true
module Dynflow
  class Middleware
    include Algebrick::TypeCheck

    def initialize(stack)
      @stack = Type! stack, Stack
    end

    # call `pass` to get deeper with the call
    def pass(*args)
      @stack.pass(*args)
    end

    # to get the action object
    def action
      @stack.action or raise "the action is not available"
    end

    def delay(*args)
      pass(*args)
    end

    def run(*args)
      pass(*args)
    end

    def plan(*args)
      pass(*args)
    end

    def finalize(*args)
      pass(*args)
    end

    def plan_phase(*args)
      pass(*args)
    end

    def finalize_phase(*args)
      pass(*args)
    end

    def present
      pass
    end

    def hook(*args)
      pass(*args)
    end
  end
end
