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

      def handle_work(work_item)
        work_item.execute
        @director.work_finished(work_item)
      end

      def event(execution_plan_id, step_id, event, future = Concurrent::Promises.resolvable_future)
        event = (Director::Event[SecureRandom.uuid, execution_plan_id, step_id, event, future])
        @director.handle_event(event).each do |work_item|
          @work_items << work_item
        end
        future
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
