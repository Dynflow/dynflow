module Dynflow
  class DeadLetterHandler < Concurrent::Actor::DefaultDeadLetterHandler

    class << self
      def drop_matchers
        @matchers ||= []
      end

      def should_drop?(dead_letter)
        drop_matchers.any? { |matcher| matcher.match? dead_letter }
      end

      def drop_matcher(*args)
        drop_matchers << Matcher.new(*args)
      end
    end

    def on_message(dead_letter)
      super unless self.class.should_drop?(dead_letter)
    end

    private

    class Matcher
      Any = Algebrick.atom

      def initialize(from, message = Any, to = Any)
        @from = from
        @message = message
        @to = to
      end

      def match?(dead_letter)
        (@from == Any || dead_letter.sender.actor_class == @from) &&
          (@message == Any || dead_letter.message == @message) &&
          (@to == Any || dead_letter.address.actor_class == @to)
      end
    end
  end
end
