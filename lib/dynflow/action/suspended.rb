module Dynflow
  class Action::Suspended

    attr_reader :execution_plan_id, :step_id

    def initialize(action)
      @world = action.world
      @execution_plan_id = action.execution_plan_id
      @step_id = action.run_step_id
    end

    def resume(method, *args)
      @world.executor.resume(@execution_plan_id, @step_id, method, *args)
    end

  end
end
