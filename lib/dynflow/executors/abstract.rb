module Dynflow
  module Executors
    class Abstract
      include Algebrick::TypeCheck
      attr_reader :world, :logger

      def initialize(world)
        @world  = Type! world, World
        @logger = world.logger
      end

      # @param execution_plan_id [String] id of execution plan
      # @param finished [Concurrent::Edge::Future]
      # @param wait_for_acceptance [TrueClass|FalseClass] should the executor confirm receiving
      # the event, disable if calling executor from within executor
      # @return [Concurrent::Edge::Future]
      # @raise when execution_plan_id is not accepted
      def execute(execution_plan_id, finished = Concurrent.future, wait_for_acceptance = true)
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
