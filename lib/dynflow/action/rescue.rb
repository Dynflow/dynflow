module Dynflow
  module Action::Rescue

    Strategy = Algebrick.type do
      variants Skip = atom, Pause = atom, Revert = atom, Fail = atom
    end

    SuggestedStrategy = Algebrick.type do
      fields! action:   Action,
              strategy: Strategy
    end

    # What strategy should be used for rescuing from error in
    # the action or its sub actions
    #
    # @return Strategy
    #
    # When determining the strategy, the algorithm starts from the
    # entry action that by default takes the strategy from #rescue_strategy_for_self
    # and #rescue_strategy_for_planned_actions and combines them together.
    def rescue_strategy
      suggested_strategies = []

      # We need to consider that action if it has at least one non-pending step
      if self.steps.compact.any? { |step| step.state != :pending }
        suggested_strategies << SuggestedStrategy[self, rescue_strategy_for_self]
      end

      self.planned_actions.each do |planned_action|
        rescue_strategy = rescue_strategy_for_planned_action(planned_action)
        next unless rescue_strategy # ignore actions that have no say in the rescue strategy
        suggested_strategies << SuggestedStrategy[planned_action, rescue_strategy]
      end

      combine_suggested_strategies(suggested_strategies)
    end

    # Override when another strategy should be used for rescuing from
    # error on the action
    def rescue_strategy_for_self
      return Pause
    end

    # Override when the action should override the rescue
    # strategy of an action it planned
    def rescue_strategy_for_planned_action(action)
      action.rescue_strategy
    end

    # Override when different approach should be taken for combining
    # the suggested strategies
    # The default behavior is:
    #   If all the actions can and want to revert, revert
    #   If all the actions which have an error in their subtree want to skip/fail, skip/fail
    #   Fail otherwise
    def combine_suggested_strategies(suggested_strategies)
      # Return Revert if all the strategies want to revert
      return Revert if suggested_strategies.all? { |strategy| strategy.strategy == Revert }

      # Select those action which have an error in their subtree
      error = suggested_strategies.select { |strategy| strategy.action.has_children_in_error? }

      # If we are in a subtree with errors
      unless error.empty?
        strategies = error.map(&:strategy).uniq # Get all the strategies
        # Check if all the strategies are the same and they're not Revert
        # We want to skip/fail if all errorneous steps want to skip/fail
        return strategies.first if strategies.count == 1 && strategies.first != Revert
      end

      # Don't know what to do, just Pause
      return Pause
    end

    # We need to keep track if there is an action with steps in error state
    def has_children_in_error?
      # TODO: Cache planned_action somewhere
      @has_children_in_error ||= self.steps.compact.any? { |step| step.state == :error } ||
                                 self.planned_actions.any? { |action| action.has_children_in_error? }
    end
  end
end

