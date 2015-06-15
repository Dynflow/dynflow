module Dynflow
  module Testing
    class DummyExecutor
      attr_reader :world

      def initialize(world)
        @world             = world
        @events_to_process = []
      end

      def event(execution_plan_id, step_id, event, future = Concurrent.future)
        @events_to_process << [execution_plan_id, step_id, event, future]
      end

      # returns true if some event was processed.
      def progress
        events = @events_to_process.dup
        clear
        events.each do |execution_plan_id, step_id, event, future|
          future.success true
          if event && world.action.state != :suspended
            return false
          end
          world.action.execute event
        end
      end

      def clear
        @events_to_process.clear
      end
    end
  end
end
