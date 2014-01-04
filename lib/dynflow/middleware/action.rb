module Dynflow
  module Middleware::Action

    class MiddlewareRegister

      attr_reader :rules

      def initialize
        @rules = Hash.new do |h, k|
          h[k] = { before:  [],
                   after:   [],
                   replace: [] }
        end
      end

      def use(middleware_class, options = {})
        @rules[middleware_class].merge!(options) do |key, old, new|
          old + Array(new)
        end
      end
    end

    def middleware
      @middleware ||= MiddlewareRegister.new
    end

  end
end
