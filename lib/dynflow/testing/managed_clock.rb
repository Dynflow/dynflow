module Dynflow
  module Testing
    class ManagedClock
      def initialize
        @pings = []
      end

      def ping(who, time, with_what = nil, where = :<<)
        @pings << [who, [where, with_what].compact]
      end

      def progress
        copy = @pings.dup
        clear
        copy.each { |who, args| who.send *args }
      end

      def clear
        @pings.clear
      end
    end
  end
end
