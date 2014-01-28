module Dynflow
  module Listeners
    class Abstract
      include Algebrick::TypeCheck
      attr_reader :world, :logger

      def initialize(world)
        @world  = Type! world, World
        @logger = world.logger
      end

      def terminate(future = Future.new)
        raise NotImplementedError
      end
    end
  end
end
