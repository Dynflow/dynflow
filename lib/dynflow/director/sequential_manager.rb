module Dynflow
  class Director
    class SequentialManager
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
        reset_finalize_steps
        unless execution_plan.error?
          step_id = execution_plan.finalize_flow.all_step_ids.first
          action_class = execution_plan.steps[step_id].action_class
          world.middleware.execute(:finalize_phase, action_class, execution_plan) do
            dispatch(execution_plan.finalize_flow)
          end
        end
        @done = true
      end

      def reset_finalize_steps
        execution_plan.finalize_flow.all_step_ids.each do |step_id|
          step       = execution_plan.steps[step_id]
          step.state = :pending if [:success, :error].include? step.state
        end
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
        return step.state != :error
      end

      def with_state_updates(&block)
        execution_plan.update_state(:running)
        block.call
        execution_plan.update_state(execution_plan.error? ? :paused : :stopped)
      end
    end
  end
end
