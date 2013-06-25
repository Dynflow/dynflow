module Dynflow
  module Initiators
    class ExecutorInitiator

      attr_reader :executor_class

      def initialize(args={})
        @executor_class = args.fetch(:executor, Executors::Executor)
      end

      def start(plan)
        executor = @executor_class.new(:plan => plan)
        executor.execute
      end

    end
  end
end
