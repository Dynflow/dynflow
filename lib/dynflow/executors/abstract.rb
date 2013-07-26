module Dynflow
  module Executors
    class Abstract
      attr_reader :world

      def initialize(world)
        @world = world
      end

      def execute(execution_plan_id)
        raise NotImplementedError
      end

    end
  end
end
