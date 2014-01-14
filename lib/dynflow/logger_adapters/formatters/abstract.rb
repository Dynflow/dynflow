module Dynflow
  module LoggerAdapters
    module Formatters
      class Abstract
        def initialize(base)
          @base = base
        end

        [:fatal, :error, :warn, :info, :debug].each do |method|
          define_method method do |message, &block|
            if block
              @base.send method, &-> { format(block.call) }
            else
              @base.send method, format(message)
            end
          end
        end

        def level=(v)
          @base.level = v
        end

        def level
          @base.level
        end

        def format(message)
          raise NotImplementedError
        end
      end
    end
  end
end
