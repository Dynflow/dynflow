module Dynflow
  module Testing
    class ManagedClock

      attr_reader :pending_pings

      include Algebrick::Types
      Timer = Algebrick.type do
        fields! who:   Object, # to ping back
                when:  type { variants Time, Numeric }, # to deliver
                what:  Maybe[Object], # to send
                where: Symbol # it should be delivered, which method
      end

      module Timer
        include Clock::Timer
      end

      def initialize
        @pending_pings = []
      end

      def ping(who, time, with_what = nil, where = :<<)
        with = with_what.nil? ? None : Some[Object][with_what]
        @pending_pings << Timer[who, time, with, where]
      end

      def progress
        copy = @pending_pings.dup
        clear
        copy.each { |ping| ping.apply }
      end

      def clear
        @pending_pings.clear
      end
    end
  end
end
