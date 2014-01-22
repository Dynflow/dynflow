module Dynflow
  class Middleware::Register
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

    def merge!(register)
      register.rules.each do |klass, rules|
        use(klass, rules)
      end
    end
  end
end
