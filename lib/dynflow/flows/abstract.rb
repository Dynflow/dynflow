# frozen_string_literal: true
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

      def self.new_from_hash(hash)
        if hash.is_a? Hash
          check_class_matching hash
          new(hash[:flows].map { |flow_hash| from_hash(flow_hash) })
        elsif hash.is_a? Integer
          Flows::Atom.new(hash)
        else
          kind, *subflows = hash
          klass = AbstractComposed::FLOW_SERIALIZATION_MAP[kind] || raise("Unknown composed flow type")
          klass.new(subflows.map { |subflow| self.new_from_hash(subflow) })
        end
      end
    end
  end
end
