module Dynflow
  module Testing

    # when extended into Class or an_object it makes all instances of the class or the object
    # mimic the supplied types. It does so by hooking into kind_of? method.
    # @example
    #   m = mock('product')
    #   m.is_a? ::Product # => false
    #   m.extend Mimic
    #   m.mimic! ::Product
    #   m.is_a? ::Product # => true
    module Mimic
      class ::Module
        def ===(v)
          v.kind_of? self
        end
      end

      def mimic!(*types)
        define =-> _ do
          define_method :mimic_types do
            types
          end
          define_method :kind_of? do |type|
            types.any? { |t| t <= type } || super(type)
          end

          alias_method :is_a?, :kind_of?
        end

        if self.kind_of? ::Class
          self.class_eval &define
        else
          self.singleton_class.class_eval &define
        end

        self
      end
    end
  end
end
