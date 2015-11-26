require 'tsort'

module Dynflow
  class Middleware::Resolver

    include TSort
    include Algebrick::TypeCheck

    def initialize(register)
      @register = Type! register, Middleware::Register
    end

    def result
      @result ||= begin
        @deps = normalize_rules(@register.rules)
        self.tsort
      end
    end

    private

    # Takes eliminate :replace and :before rules.
    # Returns hash, that maps middleware classes to their dependencies
    def normalize_rules(rules)
      deps          = Hash.new { |h, k| h[k] = [] }
      substitutions = {}

      # replace before with after on oposite direction and build the
      # substitutions dictionary
      rules.each do |middleware_class, middleware_rules|
        deps[middleware_class].concat(middleware_rules[:after])
        middleware_rules[:before].each do |dependent_class|
          deps[dependent_class] << middleware_class
        end
        middleware_rules[:replace].each do |replaced|
          substitutions[replaced] = middleware_class
        end
      end

      # replace the middleware to be substituted
      substitutions.each do |old, new|
        deps[new].concat(deps[old])
        deps.delete(old)
      end

      # ignore deps, that are not present in the stack
      deps.each do |middleware_class, middleware_deps|
        middleware_deps.reject! { |dep| !deps.has_key?(dep) }
      end

      return deps.delete_if {|klass, _| klass.nil? }
    end

    def tsort_each_node(&block)
      @deps.each_key(&block)
    end

    def tsort_each_child(node, &block)
      @deps.fetch(node).each(&block)
    end

  end
end
