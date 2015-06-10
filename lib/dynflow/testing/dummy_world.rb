module Dynflow
  module Testing
    class DummyWorld
      extend Mimic
      mimic! World

      attr_reader :clock, :executor, :middleware
      attr_accessor :action

      def initialize
        @logger_adapter = Testing.logger_adapter
        @clock          = ManagedClock.new
        @executor       = DummyExecutor.new(self)
        @middleware     = Middleware::World.new
      end

      def action_logger
        @logger_adapter.action_logger
      end

      def logger
        @logger_adapter.dynflow_logger
      end

      def silence_logger!
        action_logger.level = 4
      end

      def subscribed_actions(klass)
        []
      end

      def event(execution_plan_id, step_id, event, future = Concurrent.future)
        executor.event execution_plan_id, step_id, event, future
      end

      def persistence
        nil
      end

    end
  end
end
