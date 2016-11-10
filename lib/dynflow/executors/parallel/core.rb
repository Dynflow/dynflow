module Dynflow
  module Executors
    class Parallel < Abstract

      class Core < Actor
        attr_reader :logger

        def initialize(world, pool_size)
          @logger     = world.logger
          @world      = Type! world, World
          @pool       = Pool.spawn('pool', reference, pool_size, world.transaction_adapter)
          @terminated = nil
          @director   = Director.new(@world)
        end

        def handle_execution(execution_plan_id, finished)
          if terminating?
            raise Dynflow::Error,
                  "cannot accept execution_plan_id:#{execution_plan_id} core is terminating"
          end

          feed_pool(@director.start_execution(execution_plan_id, finished))
        end

        def handle_event(event)
          Type! event, Director::Event
          if terminating?
            raise Dynflow::Error,
                  "cannot accept event: #{event} core is terminating"
          end
          feed_pool(@director.handle_event(event))
        end

        def work_finished(work)
          feed_pool(@director.work_finished(work))
        end

        def handle_persistence_error(error)
          logger.fatal "PersistenceError in executor: terminating"
          logger.fatal error
          @world.terminate
        end

        def start_termination(*args)
          super
          logger.info 'shutting down Core ...'
          @pool.tell([:start_termination, Concurrent.future])
        end

        def finish_termination
          @director.terminate
          logger.error '... core terminated.'
          super
        end

        private

        def on_message(message)
          super
        rescue Errors::PersistenceError => e
          self.tell(:handle_persistence_error, e)
        end

        def feed_pool(work_items)
          return if terminating?
          return if work_items.nil?
          work_items = [work_items] if work_items.is_a? Director::WorkItem
          work_items.all? { |i| Type! i, Director::WorkItem }
          work_items.each { |new_work| @pool.tell([:schedule_work, new_work]) }
        end
      end
    end
  end
end
