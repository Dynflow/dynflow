module Dynflow
  module Executors
    class Abstract
      include Algebrick::TypeCheck
      attr_reader :world, :logger

      def initialize(world)
        @world  = is_kind_of! world, World
        @logger = world.logger
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
