module Dynflow
  module ExecutionPlan::Hooks
    # @abstract Subclass and override either {#execute} or `#on_*` methods to implement the desired behavior.
    class Abstract
      # @param kind [Symbol] one of {HOOK_KINDS}
      # @param execution_plan [ExecutionPlan] the execution plan which triggered the hook
      # @param action [Action] the action which defined the hook
      # @return [void]
      def execute(kind, execution_plan, action)
        raise "Unknown kind '#{kind}'" unless Dynflow::ExecutionPlan::Hooks::HOOK_KINDS.include?(kind)
        self.method("on_#{kind}".to_sym).call execution_plan, action
      end

      # @!macro [attach] hook
      #   @method on_$1(execution_plan, action)
      #   Method to execute when the execution plan goes into $1 state
      #   @param execution_plan [ExecutionPlan] the execution plan which triggered the hook
      #   @param action [Action] the action which defined the hook
      #   @return [void]
      def self.hook(kind)
        define_method "on_#{kind}".to_sym, proc { |_execution_plan, _action| nil }
      end

      hook :paused
      hook :planned
      hook :planning
      hook :running
      hook :scheduled
      hook :stopped

      # @!method on_failure(execution_plan, action)
      #   Method to execute when the execution plan goes into stopped state with error, warning or cancelled result.
      #   @param execution_plan [ExecutionPlan] the execution plan which triggered the hook
      #   @param action [Action] the action which defined the hook
      #   @return [void]
      hook :failure
      # @!method on_success(execution_plan, action)
      #   Method to execute when the execution plan goes into stopped state with success result.
      #   @param execution_plan [ExecutionPlan] the execution plan which triggered the hook
      #   @param action [Action] the action which defined the hook
      #   @return [void]
      hook :success
    end
  end
end
