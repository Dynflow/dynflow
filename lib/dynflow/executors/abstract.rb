module Dynflow
  module Executors
    class Abstract
      include Algebrick::TypeCheck
      attr_reader :world, :logger

      def initialize(world)
        @world  = Type! world, World
        @logger = world.logger
      end

      # @return [Future]
      # @raise when execution_plan_id is not accepted
      def execute(execution_plan_id)
        raise NotImplementedError
      end

      def event(execution_plan_id, step_id, event, future = Future)
        raise NotImplementedError
      end

      def terminate(future = Future.new)
        raise NotImplementedError
      end

      # @return [Future]
      def initialized
        raise NotImplementedError
      end
    end
  end
end
