module Dynflow
  module Testing
    class ManagedClock

      attr_reader :pending_pings

      include Algebrick::Types

      def initialize
        @pending_pings = []
      end

      def ping(who, time, with_what = nil, where = :<<)
        time = current_time + time if time.is_a? Numeric
        with = with_what.nil? ? None : Some[Object][with_what]
        @pending_pings << Clock::Timer[who, time, with, where]
        @pending_pings.sort!
      end

      def progress
        if next_ping = @pending_pings.shift
          # we are testing an isolated system = we can move in time
          # without actually waiting
          @current_time = next_ping.when
          next_ping.apply
        end
      end

      def current_time
        @current_time ||= Time.now
      end

      def clear
        @pending_pings.clear
      end
    end
  end
end
