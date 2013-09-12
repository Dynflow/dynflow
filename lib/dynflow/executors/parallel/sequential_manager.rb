module Dynflow
  module Executors
    class Parallel::SequentialManager
      attr_reader :execution_plan, :world

      def initialize(world, execution_plan)
        @world          = world
        @execution_plan = execution_plan
        @done           = false
      end

      def run
        with_state_updates do
          dispatch(execution_plan.run_flow)
          finalize
        end

        return execution_plan
      end

      def finalize
        unless execution_plan.error?
          world.transaction_adapter.transaction do
            unless dispatch(execution_plan.finalize_flow)
              world.transaction_adapter.rollback
            end
          end
        end
        @done = true
      end

      def done?
        @done
      end

      private

      def dispatch(flow)
        case flow
        when Flows::Sequence
          run_in_sequence(flow.flows)
        when Flows::Concurrence
          run_in_concurrence(flow.flows)
        when Flows::Atom
          run_step(execution_plan.steps[flow.step_id])
        else
          raise ArgumentError, "Don't know how to run #{flow}"
        end
      end

      def run_in_sequence(steps)
        steps.all? { |s| dispatch(s) }
      end

      def run_in_concurrence(steps)
        run_in_sequence(steps)
      end

      def run_step(step)
        step.execute
        execution_plan.update_meta_data step.execution_time
        execution_plan.save
        return step.state != :error
      end

      def with_state_updates(&block)
        execution_plan.set_state(:running)
        block.call
        execution_plan.set_state(execution_plan.error? ? :paused : :stopped)
      end
    end
  end
end
