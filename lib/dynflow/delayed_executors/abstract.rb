# frozen_string_literal: true

module Dynflow
  module DelayedExecutors
    class Abstract

      attr_reader :core

      def initialize(world, options = {})
        @world = world
        @options = options
        @started = false
        spawn
      end

      def started?
        @started
      end

      def start
        @core.ask(:start).tap do
          @started = true
        end
      end

      def terminate
        @core.ask(:terminate!)
      end

      def spawn
        Concurrent::Promises.resolvable_future.tap do |initialized|
          @core = core_class.spawn name: 'delayed-executor',
                                   args: [@world, @options],
                                   initialized: initialized
        end
      end

      private

      def core_class
        raise NotImplementedError
      end

    end
  end
end
