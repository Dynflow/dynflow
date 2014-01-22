module Dynflow
  class Middleware::World

    def initialize
      @register = Middleware::Register.new
    end

    def use(*args)
      @register.use(*args)
    end

    def execute(method, action_or_class, *args, &block)
      if action_or_class.is_a? Class
        action = nil
        action_class = action_or_class
      else
        action = action_or_class
        action_class = action.action_class
      end

      classes = middleware_classes(action_class)
      stack   = Middleware::Stack.new(classes, method, action, &block)
      stack.pass(*args)
    end

    def cumulate_register(action_class, register = Middleware::Register.new)
      unless action_class == Dynflow::Action
        cumulate_register(action_class.superclass, register)
      end
      register.merge!(action_class.middleware)
      return register
    end

    def middleware_classes(action_class)
      register = cumulate_register(action_class)
      resolver = Dynflow::Middleware::Resolver.new(register)
      resolver.result
    end

  end
end
