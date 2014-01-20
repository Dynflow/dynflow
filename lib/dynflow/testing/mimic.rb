module Dynflow
  module Testing
    module Mimic
      class ::Module
        def ===(v)
          v.kind_of? self
        end
      end

      def mimic!(*types)
        define =-> _ do
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
