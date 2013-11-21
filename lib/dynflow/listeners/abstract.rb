module Dynflow
  module Listeners
    class Abstract
      include Algebrick::TypeCheck
      attr_reader :world, :logger

      def initialize(world)
        @world  = Type! world, World
        @logger = world.logger
      end
    end
  end
end
