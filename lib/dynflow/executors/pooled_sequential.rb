module Dynflow
  module Executors
    class PooledSequential < Abstract
      def initialize(world, pool_size = 4)
        super(world)
        @queue        = Queue.new
        @free_workers = Array.new(pool_size) { Thread.new { work } }
      end

      # @returns [Future] value of the future is set when computation is finished
      #     value can be result or an error
      def execute(execution_plan_id)
        @queue.push [execution_plan_id, future = Future.new]
        return future
      end

      private

      def work
        loop do
          begin
            execution_plan_id, future = @queue.pop
            sequential                = SequentialManager.new(world, execution_plan_id)
            with_active_record_pool do
              sequential.run
              future.set(sequential.execution_plan)
            end
          rescue => error
            # TODO use logger
            # $stderr.puts "FATAL #{error.message} (#{error.class})\n#{error.backtrace.join("\n")}"
            future.set error
          end
        end
      end

      # TODO extract to an adapter
      # free connection back to pool
      def with_active_record_pool(&block)
        if defined? ActiveRecord
          ActiveRecord::Base.connection_pool.with_connection(&block)
        else
          block.call
        end
      end

    end
  end
end
