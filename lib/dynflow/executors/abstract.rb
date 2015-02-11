module Dynflow
  module Executors
    class Abstract
      Event = Algebrick.type do
        fields! execution_plan_id: String,
                step_id:           Fixnum,
                event:             Object,
                result:            Concurrent::IVar
      end

      include Algebrick::TypeCheck
      attr_reader :world, :logger

      def initialize(world)
        @world  = Type! world, World
        @logger = world.logger
      end

      # @return [Concurrent::IVar]
      # @raise when execution_plan_id is not accepted
      def execute(execution_plan_id)
        raise NotImplementedError
      end

      def event(execution_plan_id, step_id, event, future = Concurrent::IVar.new)
        raise NotImplementedError
      end

      def terminate(future = Concurrent::IVar.new)
        raise NotImplementedError
      end

      # @return [Concurrent::IVar]
      def initialized
        raise NotImplementedError
      end
    end
  end
end
