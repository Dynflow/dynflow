module Dynflow
  module Executors
    class Abstract
      include Algebrick::TypeCheck
      attr_reader :world, :logger

      def initialize(world)
        @world  = Type! world, World
        @logger = world.logger
      end

      # @return [Concurrent::Edge::Future]
      # @raise when execution_plan_id is not accepted
      def execute(execution_plan_id)
        raise NotImplementedError
      end

      def event(execution_plan_id, step_id, event, future = Concurrent.future)
        raise NotImplementedError
      end

      def terminate(future = Concurrent.future)
        raise NotImplementedError
      end

      # @return [Concurrent::Edge::Future]
      def initialized
        raise NotImplementedError
      end
    end
  end
end
