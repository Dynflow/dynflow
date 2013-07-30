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

      def run_in_sequence(execution_plan, steps)
        steps.each { |s| dispatch execution_plan, s }
      end

      def run_in_concurrence(execution_plan, steps)
        run_in_sequence(execution_plan, steps)
      end

      def work
        loop do
          begin
            execution_plan_id, future = @queue.pop
            execution_plan = world.persistence.load_execution_plan(execution_plan_id)
            with_active_record_pool do
              future.set run_execution_plan execution_plan

            end
          rescue => error
            # TODO use logger instead
            $stderr.puts "FATAL #{error.message} (#{error.class})\n#{error.backtrace.join("\n")}"
            future.set error
          end
        end
      end

      def dispatch(execution_plan, flow)
        case flow
        when Flows::Sequence
          run_in_sequence(execution_plan, flow.flows)
        when Flows::Concurrence
          run_in_concurrence(execution_plan, flow.flows)
        when Flows::Atom
          run_step(execution_plan, execution_plan.steps[flow.step_id])
        else
          raise ArgumentError, "Don't know how to run #{flow}"
        end
      end

      def run_step(execution_plan, step)
        step.execute
        execution_plan.save
      end

      def run_execution_plan(execution_plan)
        dispatch execution_plan, execution_plan.run_flow

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
