module Dynflow
  module Flows
    class Atom < Abstract

      attr_reader :step

      def to_hash
        super.merge(:step => step.to_hash)
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

      protected

      def self.new_from_hash(hash, execution_plan)
        check_class_matching hash
        new ExecutionPlan::Steps::Abstract.from_hash(hash[:step], execution_plan)
      end

    end
  end
end
