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
      def execute(execution_plan)
        @queue.push [execution_plan, future = Future.new]
        return future
      end

      private

      def run_in_sequence(steps)
        steps.each { |s| dispatch s }
      end

      def run_in_concurrence(steps)
        run_in_sequence(steps)
      end

      def work
        loop do
          execution_plan, future = @queue.pop
          with_active_record_pool do
            future.set begin
                         run_execution_plan execution_plan
                       rescue => error
                         # TODO use logger instead
                         $stderr.puts "FATAL #{error.message} (#{error.class})\n#{error.backtrace.join("\n")}"
                         error
                       end
          end
        end
      end

      def dispatch(flow)
        case flow
        when Flows::Sequence
          run_in_sequence(flow.flows)
        when Flows::Concurrence
          run_in_concurrence(flow.flows)
        when Flows::Atom
          run_step(flow.step)
        else
          raise ArgumentError, "Don't know how to run #{flow}"
        end
      end

      def run_step(step)
        step.execute
        world.persistence_adapter.save_execution_plan step.execution_plan.id, step.execution_plan.to_hash
      end

      def run_execution_plan(execution_plan)
        dispatch execution_plan.run_flow

        # TODO run finalize phase
        # bus.in_transaction_if_possible do
        #   bus.rollback_transaction unless finalize_execution_plan(execution_plan)
        # end

        return execution_plan
      end

      # TODO extract to an adapter
      # free connection back to pool
      def with_active_record_pool(&block)
        if defined? ActiveRecord
          ActiveRecord::Base.connection_pool.with_connection &block
        else
          block.call
        end
      end
    end
  end
end
