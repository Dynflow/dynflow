module Dynflow
  module DelayedExecutors
    class Polling < Abstract

      def core_class
        Dynflow::DelayedExecutors::PollingCore
      end

    end

    class PollingCore < AbstractCore
      attr_reader :poll_interval

      def configure(options)
        super(options)
        @poll_interval = options[:poll_interval]
      end

      def start
        check_delayed_plans
      end

      def check_delayed_plans
        check_time = time
        plans = delayed_execution_plans(check_time)
        process plans, check_time

        world.clock.ping(self, poll_interval, :check_delayed_plans)
      end
    end
  end
end
