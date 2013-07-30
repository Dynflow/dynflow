module Dynflow
  module Action::FlowPhase

    def self.included(base)
      base.extend(ClassMethods)
      base.attr_indifferent_access_hash :input, :output
    end

    def initialize(attributes, world)
      super attributes, world

      self.input  = attributes[:input]
      self.output = attributes[:output] || {}
    end

    def to_hash
      super.merge input:  input,
                  output: output,
                  error:  error
    end

    module ClassMethods
      def new_from_hash(hash, state, world)
        new(hash.merge(state: state), world)
      end
    end
  end
end
