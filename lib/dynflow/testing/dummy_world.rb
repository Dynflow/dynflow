# frozen_string_literal: true
module Dynflow
  module Testing
    class DummyWorld
      extend Mimic
      mimic! World

      attr_reader :clock, :executor, :middleware
      attr_accessor :action

      def initialize(_config = nil)
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

      def event(execution_plan_id, step_id, event, future = Concurrent::Promises.resolvable_future)
        executor.event execution_plan_id, step_id, event, future
      end

      def plan_event(execution_plan_id, step_id, event, time, accepted = Concurrent::Promises.resolvable_future)
        if time.nil? || time < Time.now
          event(execution_plan_id, step_id, event, accepted)
        else
          clock.ping(executor, time, Director::Event[SecureRandom.uuid, execution_plan_id, step_id, event, accepted], :delayed_event)
        end
      end

      def persistence
        nil
      end
    end
  end
end
