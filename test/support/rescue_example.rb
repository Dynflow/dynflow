require 'logger'

module Support
  module RescueExample

    class ComplexActionWithSkip < Dynflow::Action

      def plan(error_state)
        sequence do
          concurrence do
            plan_action(ActionWithSkip, 3, :success)
            plan_action(ActionWithSkip, 4, error_state)
          end
          plan_action(ActionWithSkip, 5, :success)
        end
      end

      def rescue_strategy_for_self
        Dynflow::Action::Rescue::Skip
      end

    end

    class ComplexActionWithoutSkip < ComplexActionWithSkip

      def rescue_strategy_for_planned_action(action)
        # enforce pause even when error on skipable action
        Dynflow::Action::Rescue::Pause
      end

    end

    class AbstractAction < Dynflow::Action

      def plan(identifier, desired_state)
        plan_self(identifier: identifier, desired_state: desired_state)
      end

      def run
        case input[:desired_state].to_sym
        when :success, :error_on_finalize
          output[:message] = 'Been here'
        when :error_on_run, :error_on_skip
          raise 'some error as you wish'
        when :pending
          raise 'we were not supposed to get here'
        else
          raise "unkown desired state #{input[:desired_state]}"
        end
      end

      def finalize
        case input[:desired_state].to_sym
        when :error_on_finalize, :error_on_skip
          raise 'some error as you wish'
        end
      end

    end

    class ActionWithSkip < AbstractAction

      def run(event = nil)
        if event === Dynflow::Action::Skip
          output[:message] = "skipped because #{self.error.message}"
          raise 'we failed on skip as well' if input[:desired_state].to_sym == :error_on_skip
        else
          super()
        end
      end

      def rescue_strategy_for_self
        Dynflow::Action::Rescue::Skip
      end

    end

    class ActionWithFail < AbstractAction

      def rescue_strategy_for_self
        Dynflow::Action::Rescue::Fail
      end

    end

    class ComplexActionWithFail < ActionWithFail

      def plan(error_state)
        sequence do
          concurrence do
            plan_action(ActionWithFail, 3, :success)
            plan_action(ActionWithFail, 4, error_state)
          end
          plan_action(ActionWithFail, 5, :success)
        end
      end

    end

  end
end
