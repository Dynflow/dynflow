module Dynflow
  module Flows

    class Abstract < Serializable
      include Algebrick::TypeCheck

      def initialize
        raise 'cannot instantiate Flows::Abstract'
      end

      def to_hash
        { :class => self.class.name }
      end

      def empty?
        self.size == 0
      end

      def size
        raise NotImplementedError
      end

      def includes_step?(step_id)
        self.all_step_ids.any? { |s| s == step_id }
      end

      def all_step_ids
        raise NotImplementedError
      end

      def flatten!
        raise NotImplementedError
      end
    end
  end
end
