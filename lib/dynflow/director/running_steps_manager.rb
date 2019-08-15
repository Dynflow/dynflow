# frozen_string_literal: true
module Dynflow
  class Director
    # Handles the events generated while running actions, makes sure
    # the events are sent to the action only when in suspended state
    class RunningStepsManager
      include Algebrick::TypeCheck

      def initialize(world)
        @world         = Type! world, World
        @running_steps = {}
        # enqueued work items by step id
        @work_items    = QueueHash.new(Integer, WorkItem)
        # enqueued events by step id - we delay creating work items from events until execution time
        # to handle potential updates of the step object (that is part of the event)
        @events        = QueueHash.new(Integer, Director::Event)
        @events_by_request_id = {}
      end

      def terminate
        pending_work = @work_items.clear.values.flatten(1)
        pending_work.each do |w|
          if EventWorkItem === w
            w.event.result.reject UnprocessableEvent.new("dropping due to termination")
          end
        end
      end

      def add(step, work)
        Type! step, ExecutionPlan::Steps::RunStep
        @running_steps[step.id] = step
        # we make sure not to run any event when the step is still being executed
        @work_items.push(step.id, work)
        self
      end

      # @returns [TrueClass|FalseClass, Array<WorkItem>]
      def done(step)
        Type! step, ExecutionPlan::Steps::RunStep
        # update the step based on the latest finished work
        @running_steps[step.id] = step

        @work_items.shift(step.id).tap do |work|
          finish_event_result(work) { |f| f.fulfill true }
        end

        if step.state == :suspended
          return true, [create_next_event_work_item(step)].compact
        else
          while (work = @work_items.shift(step.id))
            @world.logger.debug "step #{step.execution_plan_id}:#{step.id} dropping event #{work.request_id}/#{work.event}"
            finish_event_result(work) do |f|
              f.reject UnprocessableEvent.new("Message dropped").tap { |e| e.set_backtrace(caller) }
            end
          end
          while (event = @events.shift(step.id))
            @world.logger.debug "step #{step.execution_plan_id}:#{step.id} dropping event #{event.request_id}/#{event}"
            if event.result
              event.result.reject UnprocessableEvent.new("Message dropped").tap { |e| e.set_backtrace(caller) }
            end
          end
          unless @work_items.empty?(step.id) && @events.empty?(step.id)
            raise "Unexpected item in @work_items (#{@work_items.inspect}) or @events (#{@events.inspect})"
          end
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

        step = @running_steps[event.step_id]
        unless step
          event.result.reject UnprocessableEvent.new('step is not suspended, it cannot process events')
          return []
        end

        can_run_event = @work_items.empty?(step.id)
        @events_by_request_id[event.request_id] = event
        @events.push(step.id, event)
        if can_run_event
          [create_next_event_work_item(step)]
        else
          []
        end
      end

      # turns the first event from the queue to the next work item to work on
      def create_next_event_work_item(step)
        event = @events.shift(step.id)
        return unless event
        work = EventWorkItem.new(event.request_id, event.execution_plan_id, step, event.event, step.queue)
        @work_items.push(step.id, work)
        work
      end

      # @yield [Concurrent.resolvable_future] in case the work item has an result future assigned
      # and deletes the tracked event
      def finish_event_result(work_item)
        return unless EventWorkItem === work_item
        if event = @events_by_request_id.delete(work_item.request_id)
          yield event.result if event.result
        end
      end
    end
  end
end
