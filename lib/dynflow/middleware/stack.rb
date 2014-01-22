module Dynflow
  class Middleware::Stack

    attr_reader :action, :rest

    def initialize(middleware_classes, method, action = nil, &block)
      @action = action
      @method = method
      raise ArgumentError, 'Block required' unless block
      if middleware_classes.empty?
        @bottom = true
        @block = block
      else
        top_class, *rest = middleware_classes
        @top  = top_class.new(self)
        @rest = Middleware::Stack.new(rest, method, action, &block)
      end
    end

    def pass(*args)
      if @bottom
        @block.call(*args)
      else
        if @top.respond_to?(@method)
          @top.send(@method, *args)
        else
          @rest.pass(*args)
        end
      end
    end
  end
end
