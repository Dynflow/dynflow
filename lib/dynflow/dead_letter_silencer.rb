module Dynflow
  class DeadLetterSilencer < Concurrent::Actor::DefaultDeadLetterHandler
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
        return unless dead_letter.sender.respond_to?(:actor_class)
        evaluate(dead_letter.sender.actor_class, @from) &&
          evaluate(dead_letter.message, @message) &&
          evaluate(dead_letter.address.actor_class, @to)
      end

      private

      def evaluate(thing, condition)
        case condition
        when Any
          true
        when Proc
          condition.call(thing)
        else
          condition == thing
        end
      end
    end
  end
end
