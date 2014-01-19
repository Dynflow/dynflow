module Dynflow
  class Middleware::Stack

    attr_reader :action, :rest

    def initialize(middleware_classes, method, action = nil, &block)
      @action = action
      @method = method
      if middleware_classes.empty?
        @bottom = true
        @block = block
        if @block && @action || @block.nil? && @action.nil?
          raise ArgumentError, 'Either action or block has to be passed, but not both'
        end
        if @block.nil? && !@action.respond_to?(method)
          raise ArgumentError, "The action #{action} doesn't repond to method #{method}"
        end
      else
        top_class, *rest = middleware_classes
        @top  = top_class.new(self)
        @rest = Middleware::Stack.new(rest, method, action, &block)
      end
    end

    def pass(*args)
      if @bottom
        if @block
          @block.call(*args)
        else
          @action.send(@method, *args)
        end
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
