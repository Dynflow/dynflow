# frozen_string_literal: true
module Dynflow
  class Action::Suspended
    attr_reader :execution_plan_id, :step_id

    def initialize(action)
      @world             = action.world
      @execution_plan_id = action.execution_plan_id
      @step_id           = action.run_step_id
    end

    def plan_event(event, time, sent = Concurrent::Promises.resolvable_future, optional: false, untracked: false)
      @world.plan_event(execution_plan_id, step_id, event, time, sent, optional: optional, untracked: untracked)
    end

    def event(event, sent = Concurrent::Promises.resolvable_future, optional: false)
      # TODO: deprecate 2 levels backtrace (to know it's called from clock or internaly)
      # remove lib/dynflow/clock.rb ClockReference#ping branch condition on removal.
      plan_event(event, nil, sent, optional: optional)
    end

    def <<(event = nil)
      event event
    end

    alias_method :ask, :event
  end
end
