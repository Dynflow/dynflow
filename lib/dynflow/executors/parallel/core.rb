module Dynflow
  module Executors
    class Parallel < Abstract
      class Core < Actor
        attr_reader :logger

        def initialize(world, queues_options)
          @logger         = world.logger
          @world          = Type! world, World
          @queues_options = queues_options
          @pools          = {}
          @terminated     = nil
          @director       = Director.new(@world)

          initialize_queues
        end

        def initialize_queues
          default_pool_size = @queues_options[:default][:pool_size]
          @queues_options.each do |(queue_name, queue_options)|
            queue_pool_size = queue_options.fetch(:pool_size, default_pool_size)
            @pools[queue_name] = Pool.spawn("pool #{queue_name}", reference,
                                            queue_name, queue_pool_size,
                                            @world.transaction_adapter)
          end
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
          @pools.values.each { |pool| pool.tell([:start_termination, Concurrent.future]) }
        end

        def finish_termination(pool_name)
          @pools.delete(pool_name)
          # we expect this message from all worker pools
          return unless @pools.empty?
          @director.terminate
          logger.error '... core terminated.'
          super()
        end

        def dead_letter_routing
          @world.dead_letter_handler
        end

        def execution_status(execution_plan_id = nil)
          @pools.each_with_object({}) do |(pool_name, pool), hash|
            hash[pool_name] = pool.ask!([:execution_status, execution_plan_id])
          end
        end

        private

        def on_message(message)
          super
        rescue Errors::PersistenceError => e
          self.tell([:handle_persistence_error, e])
        end

        def feed_pool(work_items)
          return if terminating?
          return if work_items.nil?
          work_items = [work_items] if work_items.is_a? Director::WorkItem
          work_items.all? { |i| Type! i, Director::WorkItem }
          work_items.each do |new_work|
            pool = @pools[new_work.queue]
            unless pool
              logger.error("Pool is not available for queue #{new_work.queue}, falling back to #{fallback_queue}")
              pool = @pools[fallback_queue]
            end
            pool.tell([:schedule_work, new_work])
          end
        end

        def fallback_queue
          :default
        end
      end
    end
  end
end
