module Dynflow
  class Action::Suspended
    attr_reader :execution_plan_id, :step_id

    def initialize(action)
      @world             = action.world
      @execution_plan_id = action.execution_plan_id
      @step_id           = action.run_step_id
    end

    def event(event, future = Concurrent.future)
      @world.event execution_plan_id, step_id, event, future
    end

    def <<(event = nil)
      event event
    end

    alias_method :ask, :event
  end
end
