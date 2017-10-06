module Dynflow
  module Middleware::Common
    class Singleton < Middleware
      # Each action tries to acquire its own lock before the action's #plan starts
      def plan(*args)
        action.singleton_lock!
        pass(*args)
      end

      # At the end of plan phase (after all actions were planned) we check
      #   if the planning failed OR if the execution plan has no more steps to execute,
      #   in which case we unlock all the locks
      def plan_phase(execution_plan, *args)
        pass(execution_plan, *args)
        if execution_plan.result == :error || (execution_plan.run_steps.none? && execution_plan.finalize_steps.none?)
          unlock_all_singleton_locks! execution_plan
        end
      end

      # At the start of #run we try to acquire action's lock unless it already holds it
      # At the end the action tries to unlock its own lock if the execution plan has no
      #   finalize phase
      def run(*args)
        action.singleton_lock! unless action.holds_singleton_lock?
        pass(*args)
        action.singleton_unlock! if execution_plan.finalize_steps.none?
      end

      # At the end of finalize phase we check if the phase finished successfully,
      #   in which case we unlock all the locks
      def finalize_phase(execution_plan, *args)
        pass(execution_plan, *args)
        unlock_all_singleton_locks!(execution_plan) if execution_plan.finalize_steps.none?(&:error)
      end

      private

      # Unlock all the singleton locks held by all actions belonging to this execution plan
      def unlock_all_singleton_locks!(execution_plan)
        execution_plan.actions.select(&:holds_singleton_lock?).each(&:singleton_unlock!)
      end
    end
  end
end
