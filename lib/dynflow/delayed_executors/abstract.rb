module Dynflow
  module DelayedExecutors
    class Abstract

      attr_reader :core

      def initialize(world, options = {})
        @world = world
        @options = options
        spawn
      end

      def start
        @core.ask(:start)
      end

      def terminate
        @core.ask(:terminate!)
      end

      private

      def core_class
        raise NotImplementedError
      end

      def spawn
        Concurrent.future.tap do |initialized|
          @core = core_class.spawn name: 'delayed-executor',
                                   args: [@world, @options],
                                   initialized: initialized
        end
      end

    end
  end
end
