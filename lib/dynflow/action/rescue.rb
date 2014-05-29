module Dynflow
  module Action::Rescue

    # What strategy should be used for rescuing from error in
    # the action or its sub actions
    #
    # @param action Dynflow::Action - action that failed
    # @param suggested_strategy [:skip, :pause]
    #
    # @return [:skip, :pause]
    #
    # When determining the strategy, the algorithm starts from the
    # lowest level (the failed action itself) and propagates the result
    # to the action that planned it.
    #
    # @example
    #
    #    class TopAction < DynflowAction
    #      def plan
    #        plan_action(SubAction, {})
    #      end
    #
    #      def rescue_strategy(action, suggested_strategy)
    #        :pause
    #      end
    #      # ...
    #    end
    #
    #    class SubAction < DynflowAction
    #      def rescue_strategy(action, suggested_strategy)
    #        :skip
    #      end
    #      # ...
    #    end
    #
    # The alhorithm:
    #   1. calls SubAction#rescue_strategy(sub_action, :pause) that returns :skip
    #   2. calls TopAction#rescue_strategy(sub_action, :skip) that returns :pause
    #
    # therefore the final strategy to be used to rescue from the error is :pause.
    # This allows both low level actions and their originators get involved in the
    # rescue process.
    #
    def rescue_strategy(action, suggested_strategy)
      if action == self
        run_rescue_strategy
      else
        planned_action_rescue_strategy(action, suggested_strategy)
      end
    end

    def run_rescue_strategy
      return :pause
    end

    def planned_action_rescue_strategy(action, suggested_strategy)
      if suggested_strategy == :skip
        return :skip
      else
        run_rescue_strategy
      end
    end
  end
end

