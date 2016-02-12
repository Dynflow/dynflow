module Dynflow
  module Semaphores
    class Stateful < Abstract

      attr_reader :free, :tickets, :waiting, :meta

      def initialize(tickets, free = tickets, meta = {})
        @tickets = tickets
        @free = free
        @waiting = []
        @meta = meta
      end

      def wait(thing)
        if get > 0
          true
        else
          @waiting << thing
          false
        end
      end

      def get_waiting
        @waiting.shift
      end

      def has_waiting?
        !@waiting.empty?
      end

      def release(n = 1)
        @free += n
        @free = @tickets unless @tickets.nil? || @free <= @tickets
        save
      end

      def save
      end

      def get(n = 1)
        if n > @free
          drain
        else
          @free -= n
          save
          n
        end
      end

      def drain
        @free.tap do
          @free = 0
          save
        end
      end

      def to_hash
        {
          :tickets => @tickets,
          :free => @free,
          :meta => @meta
        }
      end

      def self.new_from_hash(hash)
        self.new(*hash.values_at(:tickets, :free, :meta))
      end
    end
  end
end
