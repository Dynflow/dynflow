module Dynflow
  class ExecutionPlan
    module Hooks

      HOOK_KINDS = (ExecutionPlan.states + [:success, :failure]).freeze

      require 'dynflow/execution_plan/hooks/abstract'

      # A register holding information about hook classes and events
      # which should trigger the hooks.
      #
      # @attr_reader hooks [Hash<Class, Set<Symbol>>] a hash mapping hook classes to events which should trigger the hooks
      class Register
        attr_reader :hooks

        def initialize(hooks = {})
          @hooks = hooks
        end

        # Sets a hook to be run on certain events
        #
        # @param class_name [Class] class of the hook to be run
        # @param on [Symbol, Array<Symbol>] when should the hook be run, one of {HOOK_KINDS}
        # @return [void]
        def use(class_name, on: HOOK_KINDS)
          on = Array[on] unless on.kind_of?(Array)
          validate_kinds!(on)
          if hooks[class_name]
            hooks[class_name] += on
          else
            hooks[class_name] = on
          end
        end

        # Disables a hook from being run on certain events
        #
        # @param class_name [Class] class of the hook to disable
        # @param on [Symbol, Array<Symbol>] when should the hook be disabled, one of {HOOK_KINDS}
        # @return [void]
        def do_not_use(class_name, on: HOOK_KINDS)
          on = Array[on] unless on.kind_of?(Array)
          validate_kinds!(on)
          if hooks[class_name]
            hooks[class_name] -= on
            hooks.delete(class_name) if hooks[class_name].empty?
          end
        end

        # Performs a deep clone of the hooks register
        #
        # @return [Register] new deeply cloned register
        def dup
          new_hooks = hooks.reduce({}) do |acc, (key, value)|
            acc.update(key => value.dup)
          end
          self.class.new(new_hooks)
        end

        # Runs the registered hooks
        #
        # @param execution_plan [ExecutionPlan] the execution plan which triggered the hooks
        # @param action [Action] the action which triggered the hooks
        # @param kind [Symbol] the kind of hooks to run, one of {HOOK_KINDS}
        def run(execution_plan, action, kind)
          on(kind).each do |hook|
            begin
              hook.new.execute kind, execution_plan, action
            rescue => e
              execution_plan.logger.error "Failed to run hook '#{hook}' for action '#{action.class}'"
              execution_plan.logger.debug e
            end
          end
        end

        private

        # Returns which hooks should be run on certain event.
        #
        # @param kind [Symbol] what kind of hook are we looking for
        # @return [Array<Class>] list of hook classes to execute
        def on(kind)
          hooks.select { |_key, on| on.include? kind }.keys
        end

        def validate_kinds!(kinds)
          kinds.each do |kind|
            raise "Unknown hook kind '#{kind}'" unless HOOK_KINDS.include?(kind)
          end
        end
      end
    end
  end
end
