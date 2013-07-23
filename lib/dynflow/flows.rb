module Dynflow
  module Flows

    class Abstract
    end

    class Empty < Abstract
    end

    class Atom < Abstract
      attr_reader :step
      def initialize(step)
        @step = step
      end
    end

    class AbstractComposed < Abstract
      attr_reader :flows

      def initialize(flows)
        @flows = flows
      end

      #def size
      #  @flows.size
      #end

      alias_method :sub_flows, :flows
    end

    class Concurrence < AbstractComposed
    end

    class Sequence < AbstractComposed
    end
  end
end
