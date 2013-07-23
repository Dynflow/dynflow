module Dynflow
  module Executors
    class Abstract
      def run(step)
        dispatch step
      end

      protected

      def dispatch(step)
        case step
        when ExecutionPlan::Sequence
          run_sequence(step.steps)
        when ExecutionPlan::Concurrence
          run_concurrence(step.steps)
        when ExecutionPlan::RunStep then
          run_step(step)
        else
          raise ArgumentError, "Don't know how to run #{step}"
        end
      end

      def run_in_sequence(steps)
        raise NotImplementedError
      end

      def run_in_concurrence(steps)
        raise NotImplementedError
      end

      def run_step(step)
        raise NotImplementedError
      end
    end
  end
end
