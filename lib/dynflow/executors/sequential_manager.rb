module Dynflow
  module Executors

    class SequentialManager
      attr_reader :execution_plan, :world

      def initialize(world, execution_plan_id)
        @world          = world
        @execution_plan = world.persistence.load_execution_plan(execution_plan_id)
        @done           = false
      end

      def run
        with_state_updates do
          dispatch(execution_plan.run_flow)
        end

        finalize

        return execution_plan
      end

      def finalize
        with_state_updates do
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
        execution_plan.save
        return step.state != :error
      end


      def set_state(execution_plan, state)
        execution_plan.state = state
        execution_plan.save
      end

      def with_state_updates(&block)
        set_state(execution_plan, :running)
        block.call
        set_state(execution_plan, execution_plan.result == :error ? :paused : :stopped)
      end
    end
  end
end
