module Dynflow
  module Executors
    class Parallel < Abstract
      class SuspendedStepsManager
        include Algebrick::TypeCheck

        def initialize(world)
          @world           = Type! world, World
          @suspended_steps = {}
          @events          = WorkQueue.new
        end

        def add(step)
          Type! step, ExecutionPlan::Steps::RunStep
          @suspended_steps[step.id] = step
          # we make sure not to run any event when the step is still being executed
          @events.push(step.id, step)
        end

        def done(step)
          Type! step, ExecutionPlan::Steps::RunStep
          @events.shift(step.id)

          if step.state == :suspended
            return true, @events.first(step.id)
          else
            while (event = @events.shift(step.id))
              message = "step #{step.execution_plan_id}:#{step.id} dropping event #{event.event}"
              @world.logger.warn message
              event.event.result.fail UnprocessableEvent.new(message).tap { |e| e.set_backtrace(caller) }
            end
            raise 'assert' unless @events.empty?(step.id)
            @suspended_steps.delete(step.id)
            return false, nil
          end
        end

        def event(event)
          Type! event, Event

          step = @suspended_steps[event.step_id]
          unless step
            event.result.fail UnprocessableEvent.new('step is not suspended, it cannot process events')
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
