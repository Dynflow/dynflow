module Dynflow
  module Flows

    class Abstract < Serializable
      include Algebrick::TypeCheck

      def to_hash
        if self.class == Abstract
          raise "calling to_hash directly on Flows::Abstract not allowed"
        end
        { :class => self.class.name }
      end

      def self.new_from_hash(execution_plan, hash)
        flow_class = hash[:class].constantize
        flow_class.allocate.tap do |flow|
          flow.new_from_hash(execution_plan, hash)
        end
      end

      def new_from_hash(execution_plan, ahash)
        raise NotImplementedError
      end

      def empty?
        self.size == 0
      end

      def size
        raise NotImplementedError
      end

      def includes_step?(step_id)
        self.all_steps.any? { |step| step.id == step_id }
      end

      def all_steps
        raise NotImplementedError
      end

      def flatten!
        raise NotImplementedError
      end
    end
  end
end
