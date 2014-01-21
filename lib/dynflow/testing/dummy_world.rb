module Dynflow
  module Testing
    class DummyWorld
      extend Mimic
      mimic! World

      attr_reader :clock, :executor
      attr_accessor :action

      def initialize
        @logger_adapter = Testing.logger_adapter
        @clock          = ManagedClock.new
        @executor       = DummyExecutor.new(self)
      end

      def action_logger
        @logger_adapter.action_logger
      end

      def logger
        @logger_adapter.dynflow_logger
      end

      def subscribed_actions(klass)
        []
      end
    end
  end
end
