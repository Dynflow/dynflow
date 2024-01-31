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
        check_class_matching hash
        new(hash[:flows].map { |flow_hash| from_hash(flow_hash) })
      end

      def self.decode(data)
        if data.is_a? Integer
          Flows::Atom.new(data)
        else
          kind, *subflows = data
          Registry.decode(kind).new(subflows.map { |subflow| self.decode(subflow) })
        end
      end
    end
  end
end
