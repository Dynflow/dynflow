module Dynflow
  module Testing
    class ManagedClock
      def initialize
        @pings_to_process = []
      end

      def ping(who, time, with_what = nil, where = :<<)
        @pings_to_process << [who, [where, with_what].compact]
      end

      def progress
        copy = @pings_to_process.dup
        clear
        copy.each { |who, args| who.send *args }
      end

      def clear
        @pings_to_process.clear
      end
    end
  end
end
