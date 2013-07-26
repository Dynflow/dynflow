module Dynflow
  module Flows

    class Abstract
      include Algebrick::TypeCheck

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
