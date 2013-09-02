module Dynflow
  module Action::FlowPhase

    def self.included(base)
      base.extend(ClassMethods)
      base.attr_indifferent_access_hash :input, :output
    end

    def initialize(attributes, world)
      super attributes, world

      self.input  = deserialize_references(attributes[:input])
      self.output = attributes[:output] || {}
    end

    def to_hash
      super.merge input:  input,
                  output: output,
                  error:  error
    end

    def deserialize_references(value)
      case value
      when Hash
        if value[:class] == "Dynflow::ExecutionPlan::OutputReference"
          ExecutionPlan::OutputReference.new_from_hash(value)
        else
          value.reduce(HashWithIndifferentAccess.new) do |h, (key, val)|
            h.update(key => deserialize_references(val))
          end
        end
      when Array
        value.map { |val| deserialize_references(val) }
      else
        value
      end
    end

    module ClassMethods
      def new_from_hash(hash, state, world)
        new(hash.merge(state: state), world)
      end
    end
  end
end
