module Dynflow
  module Executors
    class Sequential < Abstract

      # TODO replace with the one in PR

      def initialize
        @queue  = Queue.new
        @worker = Thread.new { work }
      end

      def run(step) # TODO only async for now, return future
        @queue.push step
      end

      protected

      def run_in_sequence(steps)
        steps.each { |s| dispatch s }
      end

      def run_in_concurrence(steps)
        run_in_sequence(steps)
      end

      def run_step(step)
        step.run
      end

      private

      def work
        loop do
          begin
            dispatch @queue.pop
          rescue => e
            binding.pry
          end
        end
      end
    end
  end
end
