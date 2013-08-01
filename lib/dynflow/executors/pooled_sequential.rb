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
        steps.all? { |s| dispatch(execution_plan, s) }
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
              future.set(run_execution_plan(execution_plan))
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
        return step.state != :error
      end

      def run_execution_plan(execution_plan)
        set_state(execution_plan, :running)

        dispatch(execution_plan, execution_plan.run_flow)

        world.transaction_adapter.transaction do
          unless finalize_execution_plan(execution_plan)
            world.transaction_adapter.rollback
          end
        end

        if execution_plan.result == :error
          set_state(execution_plan, :paused)
        else
          set_state(execution_plan, :stopped)
        end

        return execution_plan
      end

      def finalize_execution_plan(execution_plan)
        dispatch(execution_plan, execution_plan.finalize_flow)
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

      private

      def set_state(execution_plan, state)
        execution_plan.state = state
        execution_plan.save
      end
    end
  end
end
