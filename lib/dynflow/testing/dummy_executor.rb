# frozen_string_literal: true

module Dynflow
  module Testing
    class DummyExecutor
      attr_reader :world, :events_to_process

      def initialize(world)
        @world             = world
        @events_to_process = []
      end

      def event(execution_plan_id, step_id, event, future = Concurrent::Promises.resolvable_future)
        @events_to_process << [execution_plan_id, step_id, event, future]
      end

      def delayed_event(director_event)
        @events_to_process << [director_event.execution_plan_id, director_event.step_id, director_event.event, director_event.result]
      end

      def plan_events(delayed_events)
        delayed_events.each do |event|
          world.plan_event(event.execution_plan_id, event.step_id, event.event, event.time)
        end
      end

      def execute(action, event = nil)
        action.execute event
        plan_events(action.delayed_events.dup)
        action.delayed_events.clear
      end

      # returns true if some event was processed.
      def progress
        events = @events_to_process.dup
        clear
        events.each do |execution_plan_id, step_id, event, future|
          future.fulfill true
          if event && world.action.state != :suspended
            return false
          end
          execute(world.action, event)
        end
      end

      def clear
        @events_to_process.clear
      end
    end
  end
end
