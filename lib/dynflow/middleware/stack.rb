# frozen_string_literal: true

module Dynflow
  class Middleware::Stack
    include Algebrick::TypeCheck

    attr_reader :action, :middleware_class, :middleware

    def self.build(middleware_classes, method, action, &block)
      middleware_classes.reverse_each.reduce(block) do |stack, klass|
        Middleware::Stack.new(stack, klass, method, action)
      end
    end

    def initialize(next_stack, middleware_class, method, action)
      @middleware_class = Child! middleware_class, Middleware
      @middleware       = middleware_class.new self
      @action           = Type! action, Dynflow::Action, NilClass
      @method           = Match! method, :delay, :plan, :run, :finalize, :plan_phase, :finalize_phase, :present, :hook
      @next_stack       = Type! next_stack, Middleware::Stack, Proc
    end

    def call(*args, **kwargs)
      @middleware.send @method, *args, **kwargs
    end

    def pass(*args, **kwargs)
      @next_stack.call(*args, **kwargs)
    end
  end
end
