require 'dynflow/executors/executor'

module Dynflow
  module Executors
    class AsyncExecutor < Executor

      attr_reader :gateway

      def initialize(args={})
        @gateway = args.fetch(:gateway)
      end

      def execute(plan)
        run(plan)
      end


      private

        def run(plan)
          step = next_step(plan)
          return step
        end

        def next_step(plan)
          case plan
            when ExecutionPlan::Sequence
              step = check_plan(plan)
            when ExecutionPlan::Concurrence
              step = check_plan(plan)
            when RunStep
              step = check_step(plan)
            when false
              return false
            else
              raise ArgumentError, "Don't know how to run #{plan}"
            end

          return step
        end

        def check_plan(plan)
          plan.steps.each do |step|
            current_step = next_step(step)
            
            if current_step
              return current_step
            end
          end
          return false
        end

        def check_step(step)
          if %w[skipped success].include?(step.status)
            return false
          else
            return step
          end
        end

    end
  end
end
