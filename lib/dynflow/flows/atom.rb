module Dynflow
  module Flows
    class Atom < Abstract

      attr_reader :step_id

      def to_hash
        super.merge(:step_id => step_id)
      end

      def initialize(step_id)
        @step_id = is_kind_of! step_id, Integer
      end

      def size
        1
      end

      def all_step_ids
        [step_id]
      end

      def flatten!
        # nothing to do
      end

      protected

      def self.new_from_hash(hash)
        check_class_matching hash
        new(hash[:step_id])
      end

    end
  end
end
