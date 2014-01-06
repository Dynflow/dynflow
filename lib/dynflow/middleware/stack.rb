module Dynflow
  class Middleware::Stack

    def initialize(middleware_classes)
      unless middleware_classes.empty?
        top_class, *rest = middleware_classes
        @top  = top_class.new
        @rest = Middleware::Stack.new(rest)
      end
    end

    def evaluate(method, action, *args)
      raise "Action doesn't respont to #{method}" unless action.respond_to?(method)
      original_thread_data = thread_data
      begin
        setup_thread_data(method, action)
        pass(*args)
      ensure
        self.thread_data = original_thread_data
      end
    end

    def pass(*args)
      raise "Middleware evaluation not setup" unless thread_data[:stack]
      original_stack = thread_data[:stack]
      begin
        thread_data[:stack] = @rest
        if top.respond_to?(thread_data[:method])
          top.send(thread_data[:method], *args)
        else
          @rest.pass(*args)
        end
      ensure
        thread_data[:stack] = original_stack
      end
    end

    def top
      @top || thread_data[:action]
    end

    def setup_thread_data(method, action)
      self.thread_data = { method: method,
                           action: action,
                           stack: self }
    end

    def thread_data
      Thread.current[:dynflow_middleware]
    end

    def thread_data=(value)
      Thread.current[:dynflow_middleware] = value
    end
  end
end
