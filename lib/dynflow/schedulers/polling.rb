module Dynflow
  module Schedulers
    class Polling < Abstract

      def core_class
        Dynflow::Schedulers::PollingCore
      end

    end

    class PollingCore < AbstractCore
      attr_reader :poll_interval

      def configure(options)
        super(options)
        @poll_interval = options[:poll_interval]
      end

      def start
        check_schedule
      end

      def check_schedule
        check_time = time
        plans = scheduled_execution_plans(check_time)
        process plans, check_time

        world.clock.ping(self, poll_interval, :check_schedule)
      end
    end
  end
end
