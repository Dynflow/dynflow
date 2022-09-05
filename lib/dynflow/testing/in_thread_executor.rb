# frozen_string_literal: true
module Dynflow
  module Testing
    class InThreadExecutor
      def initialize(world)
        @world = world
        @director = Director.new(@world)
        @work_items = Queue.new
      end

      def execute(execution_plan_id, finished = Concurrent::Promises.resolvable_future, _wait_for_acceptance = true)
        feed_queue(@director.start_execution(execution_plan_id, finished))
        process_work_items
        finished
      end

      def process_work_items
        until @work_items.empty?
          feed_queue(handle_work(@work_items.pop))
          clock_tick
        end
      end

      def plan_events(delayed_events)
        delayed_events.each do |event|
          @world.plan_event(event.execution_plan_id, event.step_id, event.event, event.time, optional: event.optional, untracked: event.untracked)
        end
      end

      def handle_work(work_item)
        work_item.execute
        step = work_item.step if work_item.is_a?(Director::StepWorkItem)
        plan_events(step && step.delayed_events) if step && step.delayed_events
        @director.work_finished(work_item)
      end

      def event(execution_plan_id, step_id, event, future = Concurrent::Promises.resolvable_future, optional: false)
        event = (Director::Event[SecureRandom.uuid, execution_plan_id, step_id, event, future, optional])
        @director.handle_event(event).each do |work_item|
          @work_items << work_item
        end
        future
      end

      def delayed_event(director_event)
        @director.handle_event(director_event).each do |work_item|
          @work_items << work_item
        end
        director_event.result
      end

      def clock_tick
        @world.clock.progress_all([:periodic_check_inbox])
      end

      def feed_queue(work_items)
        work_items.each do |work_item|
          work_item.world = @world
          @work_items.push(work_item)
        end
      end

      def terminate(future = Concurrent::Promises.resolvable_future)
        @director.terminate
        future.fulfill true
      rescue => e
        future.reject e
      end
    end
  end
end
