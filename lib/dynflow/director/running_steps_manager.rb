module Dynflow
  class Director
    # Handles the events generated while running actions, makes sure
    # the events are sent to the action only when in suspended state
    class RunningStepsManager
      include Algebrick::TypeCheck

      def initialize(world)
        @world         = Type! world, World
        @running_steps = {}
        @events        = WorkQueue.new(Integer, WorkItem)
      end

      def terminate
        pending_work = @events.clear.values.flatten(1)
        pending_work.each do |w|
          if EventWorkItem === w
            w.event.result.fail UnprocessableEvent.new("dropping due to termination")
          end
        end
      end

      def add(step, work)
        Type! step, ExecutionPlan::Steps::RunStep
        @running_steps[step.id] = step
        # we make sure not to run any event when the step is still being executed
        @events.push(step.id, work)
        self
      end

      # @returns [TrueClass|FalseClass, Array<WorkItem>]
      def done(step)
        Type! step, ExecutionPlan::Steps::RunStep
        @events.shift(step.id).tap do |work|
          work.event.result.success true if EventWorkItem === work
        end

        if step.state == :suspended
          return true, [@events.first(step.id)].compact
        else
          while (event = @events.shift(step.id))
            message = "step #{step.execution_plan_id}:#{step.id} dropping event #{event.event}"
            @world.logger.warn message
            event.event.result.fail UnprocessableEvent.new(message).
                tap { |e| e.set_backtrace(caller) }
          end
          raise 'assert' unless @events.empty?(step.id)
          @running_steps.delete(step.id)
          return false, []
        end
      end

      def try_to_terminate
        @running_steps.delete_if do |_, step|
          step.state != :running
        end
        return @running_steps.empty?
      end

      # @returns [Array<WorkItem>]
      def event(event)
        Type! event, Event
        next_work_items = []

        step = @running_steps[event.step_id]
        unless step
          event.result.fail UnprocessableEvent.new('step is not suspended, it cannot process events')
          return next_work_items
        end

        can_run_event = @events.empty?(step.id)
        work          = EventWorkItem.new(event.execution_plan_id, step, event)
        @events.push(step.id, work)
        next_work_items << work if can_run_event
        next_work_items
      end
    end
  end
end
