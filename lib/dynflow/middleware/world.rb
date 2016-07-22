module Dynflow
  class Middleware::World

    include Algebrick::TypeCheck

    def initialize
      @register = Middleware::Register.new
      clear_cache!
    end

    def use(*args)
      clear_cache!
      @register.use(*args)
    end

    def execute(method, action_or_class, *args, &block)
      Match! method, :delay, :plan, :run, :finalize, :plan_phase, :finalize_phase, :present
      if Child? action_or_class, Dynflow::Action
        action = nil
        action_class = action_or_class
      elsif Type? action_or_class, Dynflow::Action
        action = action_or_class
        action_class = action.class
      else
        Algebrick::TypeCheck.error action_or_class, 'is not instance or child class', Dynflow::Action
      end

      classes = middleware_classes(action_class)
      stack   = Middleware::Stack.build(classes, method, action, &block)
      stack.call(*args)
    end

    def clear_cache!
      @middleware_classes_cache = {}
    end

    private

    def cumulate_register(action_class, register = Middleware::Register.new)
      register.merge!(@register)
      unless action_class == Dynflow::Action
        cumulate_register(action_class.superclass, register)
      end
      register.merge!(action_class.middleware)
      return register
    end

    def middleware_classes(action_class)
      unless @middleware_classes_cache.key?(action_class)
        register = cumulate_register(action_class)
        resolver = Dynflow::Middleware::Resolver.new(register)
        @middleware_classes_cache[action_class] = resolver.result
      end
      return @middleware_classes_cache[action_class]
    end

  end
end
