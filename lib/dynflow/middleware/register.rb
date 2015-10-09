module Dynflow
  class Middleware::Register
    include Algebrick::TypeCheck

    attr_reader :rules

    def initialize
      @rules = Hash.new do |h, k|
        h[k] = { before:  [],
                 after:   [],
                 replace: [] }
      end
    end

    def use(middleware_class, options = {})
      unknown_options = options.keys - [:before, :after, :replace]
      if unknown_options.any?
        raise ArgumentError, "Unexpected options: #{unknown_options}"
      end
      @rules[middleware_class].merge!(options) do |key, old, new|
        old + Array(new)
      end
    end

    def do_not_use(middleware_class)
      use nil, :replace => middleware_class
    end

    def merge!(register)
      Type! register, Middleware::Register
      register.rules.each do |klass, rules|
        use(klass, rules)
      end
    end
  end
end
