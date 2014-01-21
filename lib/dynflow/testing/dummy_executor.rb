module Dynflow
  module Testing
    class DummyExecutor
      attr_reader :world

      def initialize(world)
        @world = world
      end

      def event(suspended_action, event, future)
        future.resolve true
        world.action.execute event
      end
    end
  end
end
