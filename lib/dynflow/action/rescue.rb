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
        rescue_strategy_for_self
      else
        rescue_strategy_for_planned_action(action, suggested_strategy)
      end
    end

    def rescue_strategy_for_self
      return :pause
    end

    def rescue_strategy_for_planned_action(action, suggested_strategy)
      if suggested_strategy == :skip
        return :skip
      else
        run_rescue_strategy
      end
    end
  end
end

