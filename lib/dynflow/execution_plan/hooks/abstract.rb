module Dynflow
  module ExecutionPlan::Hooks
    # @abstract Subclass and override {#on_success}, {#on_pause}, {#on_stop} and {#on_fail} methods to
    #   implement the desired behavior.
    class Abstract
      def execute(kind, execution_plan, action)
        raise "Unknown kind '#{kind}'" unless Dynflow::ExecutionPlan::Hooks::HOOK_KINDS.include?(kind)
        self.method("on_#{kind}".to_sym).call execution_plan, action
      end

      # Method to execute when the execution plan goes into stopped state with success result.
      #
      # @param execution_plan [ExecutionPlan] the execution plan which triggered the hook
      # @param action [Action] the action which defined the hook
      def on_success(execution_plan, action)
      end

      # Method to execute when the execution plan goes into paused state.
      #
      # @param execution_plan [ExecutionPlan] the execution plan which triggered the hook
      # @param action [Action] the action which defined the hook
      def on_pause(execution_plan, action)
      end

      # Method to execute when the execution plan goes into stopped state.
      #
      # @param execution_plan [ExecutionPlan] the execution plan which triggered the hook
      # @param action [Action] the action which defined the hook
      def on_stop(execution_plan, action)
      end

      # Method to execute when the execution plan goes into stopped state with error, warning or cancelled result.
      #
      # @param execution_plan [ExecutionPlan] the execution plan which triggered the hook
      # @param action [Action] the action which defined the hook
      def on_fail(execution_plan, action)
      end
    end
  end
end
