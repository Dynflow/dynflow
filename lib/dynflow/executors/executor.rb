module Dynflow
  module Executors
    class Executor

      attr_reader :plan, :worker

      def initialize(args)
        @plan = args[:plan]
        @worker = Worker.new
      end

      def execute
        run(@plan)
      end

      private

        def run(step)
          success =  case step
                     when ExecutionPlan::Sequence then run_sequence(step)
                     when ExecutionPlan::Concurrence then run_concurrence(step)
                     when RunStep then run_step(step)
                     else raise ArgumentError, "Don't know how to run #{step}"
                     end

          return success
        end

        def run_sequence(sequence)
          sequence.steps.each do |run_plan|
            return false if !run(run_plan)
          end
          return true
        end

        def run_concurrence(concurrence)
          success = true
          tasks = []
          threads = []

          concurrence.steps.each do |run_plan|
            threads << Thread.new do
              Thread.current['status'] = run(run_plan)

              #TODO figure out how to make this pluggable?
              ActiveRecord::Base.connection.close if Object.constants.include?(:ActiveRecord)
            end
          end

          threads.each do |thread| 
            thread.join
            success = thread['status'] && success
          end

          return success
        end

        def run_step(step)
          step.replace_references!
          
          if %w[skipped success].include?(step.status)
            return true
          else
            @worker.run(step)
          end
        end
    end
  end
end
