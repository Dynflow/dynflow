module Dynflow
  class ExecutionPlan::Rescuer

    AVAILABLE_STRATEGIES = [:pause, :skip]

    def initialize(execution_plan)
      @execution_plan = execution_plan
    end

    def suggested_strategy
      @suggested_strategy ||=
          begin
            suggested_strategies = errored_actions.map do |action|
              compute_action_strategy(action, action, :pause)
            end
            combine_strategies(suggested_strategies)
          end
    end

    # returns id of the execution plan to execute to rescue from the error
    # it might be id of new plan or the very same with some steps marked to be skipped.
    # returns nil if no execution plan can be executed to rescue from the error
    def rescue_plan_id
      case suggested_strategy
      when :pause
        nil
      when :skip
        errored_actions.each do |action|
          @execution_plan.skip(action.run_step)
        end
        @execution_plan.id
      else
        raise NotImplementedError.new "Rescue strategy #{suggested_strategy} not implemented"
      end
    end

    private

    def errored_actions
      @errored_actions ||=
          begin
            @execution_plan.actions.find_all do |action|
              action.run_step && action.run_step.state == :error
            end
          end
    end

    def combine_strategies(strategies)
      validate_strategies(strategies)
      if strategies.include?(:pause)
        :pause
      elsif strategies.all? { |s| s == :skip }
        :skip
      else
        raise "Don't know how to combine this rescue strategies: #{strategies}"
      end
    end

    def validate_strategies(strategies)
      unsupported = strategies.uniq - AVAILABLE_STRATEGIES
      if unsupported.any?
        raise "Unsupported rescue strategies: #{unsupported}"
      end
    end

    def compute_action_strategy(asked_action, failed_action, suggested_strategy)
      suggested_strategy = asked_action.rescue_strategy(failed_action, suggested_strategy)
      if next_action = asked_action.parent_action
        return compute_action_strategy(next_action, failed_action, suggested_strategy)
      else
        return suggested_strategy
      end
    end

  end
end
