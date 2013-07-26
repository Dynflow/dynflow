module Dynflow
  module Flows
    class Atom < Abstract

      attr_reader :step

      def to_hash
        super.merge(:step => step.to_hash)
      end

      def new_from_hash(execution_plan, hash)
        step = ExecutionPlan::Steps::Abstract.new_from_hash(execution_plan, hash[:step])
        initialize(step)
      end

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
