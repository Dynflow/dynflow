module Dynflow
  module Action::RunPhase

    def self.included(base)
      base.send(:include, Action::FlowPhase)
    end

    def execute
      #with_suspend do
      with_error_handling do
        run
      end
      #end
    end

    # DSL for run

    #def suspend
    #  throw :suspend_action
    #end
    #
    #private
    #
    #def with_suspend(&block)
    #  suspended = true
    #  catch :suspend_action do
    #    block.call
    #    suspended = false
    #  end
    #  if suspended
    #    # TODO suspend
    #  end
    #end
  end
end
