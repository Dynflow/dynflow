module Dynflow
  module Testing
    class InThreadExecutor < Dynflow::Executors::Abstract
      def initialize(world)
        @world = world
        @director = Director.new(@world)
        @work_items = Queue.new
      end

      def execute(execution_plan_id, finished)
        feed_queue(@director.start_execution(execution_plan_id, finished))
        process_work_items
        finished
      end

      def process_work_items
        until @work_items.empty?
          clock_tick
          feed_queue(handle_work(@work_items.pop))
        end
      end

      def handle_work(work_item)
        work_item.execute
        @director.work_finished(work_item)
      end

      def event(execution_plan_id, step_id, event, future = Concurrent.future)
        event = (Director::Event[execution_plan_id, step_id, event, future])
        @director.event(event).each do |work_item|
          @work_items << work_item
        end
        future
      end

      def clock_tick
        @world.clock.progress
      end

      def feed_queue(work_items)
        work_items.each { |work_item| @work_items.push(work_item) }
      end

      def terminate
        @director.terminate
      end
    end
  end
end
