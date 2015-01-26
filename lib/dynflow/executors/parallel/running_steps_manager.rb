module Dynflow
  module Executors
    class Parallel < Abstract

      # Handles the events generated while running actions, makes sure
      # the events are sent to the action only when in suspended state
      class RunningStepsManager
        include Algebrick::TypeCheck

        def initialize(world)
          @world         = Type! world, World
          @running_steps = {}
          @events        = WorkQueue.new(Integer, Work)
        end

        def terminate
          pending_work = @events.clear.values.flatten
          pending_work.each do |w|
            if Work::Event === w
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

        # @returns [Work, nil]
        def done(step)
          Type! step, ExecutionPlan::Steps::RunStep
          @events.shift(step.id).tap do |work|
            work.event.result.resolve true if Work::Event === work
          end

          if step.state == :suspended
            return true, @events.first(step.id)
          else
            while (event = @events.shift(step.id))
              message = "step #{step.execution_plan_id}:#{step.id} dropping event #{event.event}"
              @world.logger.warn message
              event.event.result.fail UnprocessableEvent.new(message).
                                          tap { |e| e.set_backtrace(caller) }
            end
            raise 'assert' unless @events.empty?(step.id)
            @running_steps.delete(step.id)
            return false, nil
          end
        end

        # @returns [Work, nil]
        def event(event)
          Type! event, Parallel::Event

          step = @running_steps[event.step_id]
          unless step
            event.result.fail UnprocessableEvent.new(
                                  'step is not suspended, it cannot process events')
            return nil
          end

          can_run_event = @events.empty?(step.id)
          work          = Work::Event[step, event.execution_plan_id, event]
          @events.push(step.id, work)
          work if can_run_event
        end
      end
    end
  end
end
