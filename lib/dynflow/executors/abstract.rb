module Dynflow
  module Executors
    class Abstract
      attr_reader :world

      def initialize(world)
        @world = world
      end

      # @return [Future]
      # @raise when execution_plan_id is not accepted
      def execute(execution_plan_id)
        raise NotImplementedError
      end

      def update_progress(suspended_action, done, *args)
        raise NotImplementedError
      end
    end
  end
end
