module Dynflow
  class DeadLetterHandler < Concurrent::Actor::DefaultDeadLetterHandler
    def initialize(matchers)
      @matchers = Type! matchers, Array
    end

    def should_drop?(dead_letter)
      @matchers.any? { |matcher| matcher.match? dead_letter }
    end

    def on_message(dead_letter)
      super unless should_drop?(dead_letter)
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
