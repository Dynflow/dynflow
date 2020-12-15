# frozen_string_literal: true
module Dynflow
  module Flows
    class Atom < Abstract

      attr_reader :step_id

      def encode
        step_id
      end

      def initialize(step_id)
        @step_id = Type! step_id, Integer
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

      def ==(other)
        self.class == other.class && self.step_id == other.step_id
      end

      protected

      def self.new_from_hash(hash)
        check_class_matching hash
        new(hash[:step_id])
      end

    end
  end
end
