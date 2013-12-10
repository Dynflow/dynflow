module Dynflow
  module Action::FlowPhase

    def self.included(base)
      base.extend(ClassMethods)
      base.send(:attr_reader, :input)
    end

    def initialize(attributes, world)
      super attributes, world

      indifferent_access_hash_variable_set :input, deserialize_references(attributes[:input])
      indifferent_access_hash_variable_set :output, attributes[:output] || {}
    end

    def to_hash
      super.merge recursive_to_hash(input:  input,
                                    output: output)
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
      def new_from_hash(hash, step, world)
        new(hash.merge(step: step), world)
      end
    end
  end
end
