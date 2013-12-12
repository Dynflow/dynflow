module Dynflow
  class Action::Suspended
    attr_reader :execution_plan_id, :step_id

    def initialize(action)
      @world             = action.world
      @execution_plan_id = action.execution_plan_id
      @step_id           = action.run_step_id
    end

    def event(event)
      @world.executor.event self, event
    end

    alias_method :<<, :event
  end
end
