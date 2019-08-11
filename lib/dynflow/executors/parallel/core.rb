# frozen_string_literal: true
require 'dynflow/executors/parallel/pool'
require 'dynflow/executors/parallel/worker'

module Dynflow
  module Executors
    class Parallel
      class Core < Abstract::Core
        attr_reader :logger

        def initialize(world, heartbeat_interval, queues_options)
          super
          @pools = {}
          initialize_queues
        end

        def initialize_queues
          default_pool_size = @queues_options[:default][:pool_size]
          @queues_options.each do |(queue_name, queue_options)|
            queue_pool_size = queue_options.fetch(:pool_size, default_pool_size)
            @pools[queue_name] = Pool.spawn("pool #{queue_name}", @world,
                                            reference, queue_name, queue_pool_size,
                                            @world.transaction_adapter)
          end
        end

        def start_termination(*args)
          super
          @pools.values.each { |pool| pool.tell([:start_termination, Concurrent::Promises.resolvable_future]) }
        end

        def finish_termination(pool_name)
          @pools.delete(pool_name)
          # we expect this message from all worker pools
          return unless @pools.empty?
          super()
        end

        def execution_status(execution_plan_id = nil)
          @pools.each_with_object({}) do |(pool_name, pool), hash|
            hash[pool_name] = pool.ask!([:execution_status, execution_plan_id])
          end
        end

        def feed_pool(work_items)
          work_items.each do |new_work|
            new_work.world = @world
            @pools.fetch(suggest_queue(new_work)).tell([:schedule_work, new_work])
          end
        end
      end
    end
  end
end
