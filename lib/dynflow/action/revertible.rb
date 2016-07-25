module Dynflow
  class Action
    module Revertible

      def self.revert_action_class
        raise NotImplementedError
      end

      def rescue_strategy_for_self
        Rescue::Revert
      end

    end
  end
end
