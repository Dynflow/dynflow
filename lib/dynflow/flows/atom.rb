module Dynflow
  module Flows
    class Atom < Abstract

      attr_reader :step

      def initialize(step)
        @step = is_kind_of! step, ExecutionPlan::Steps::Abstract
      end

      def size
        1
      end

      def all_steps
        [step]
      end

      def flatten!
        # nothing to do
      end
    end
  end
end
