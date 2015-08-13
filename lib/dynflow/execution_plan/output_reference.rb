module Dynflow
  class ExecutionPlan::OutputReference < Serializable
    include Algebrick::TypeCheck

    # dereferences all OutputReferences in Hash-Array structure
    def self.dereference(object, persistence)
      case object
      when Hash
        object.reduce(Utils.indifferent_hash({})) do |h, (key, val)|
          h.update(key => dereference(val, persistence))
        end
      when Array
        object.map { |val| dereference(val, persistence) }
      when self
        object.dereference(persistence)
      else
        object
      end
    end

    # dereferences all hashes representing OutputReferences in Hash-Array structure
    def self.deserialize(value)
      case value
      when Hash
        if value[:class] == self.to_s
          new_from_hash(value)
        else
          value.reduce(Utils.indifferent_hash({})) do |h, (key, val)|
            h.update(key => deserialize(val))
          end
        end
      when Array
        value.map { |val| deserialize(val) }
      else
        value
      end
    end

    attr_reader :execution_plan_id, :step_id, :action_id, :subkeys

    def initialize(execution_plan_id, step_id, action_id, subkeys = [])
      @execution_plan_id = Type! execution_plan_id, String
      @step_id           = Type! step_id, Integer
      @action_id         = Type! action_id, Integer
      Type! subkeys, Array
      @subkeys = subkeys.map { |v| Type!(v, String, Symbol).to_s }.freeze
    end

    def [](subkey)
      self.class.new(execution_plan_id, step_id, action_id, subkeys + [subkey])
    end

    def to_hash
      recursive_to_hash class:             self.class.to_s,
                        execution_plan_id: execution_plan_id,
                        step_id:           step_id,
                        action_id:         action_id,
                        subkeys:           subkeys
    end

    def to_s
      "Step(#{step_id}).output".tap do |ret|
        ret << subkeys.map { |k| "[:#{k}]" }.join('') if subkeys.any?
      end
    end

    alias_method :inspect, :to_s

    def dereference(persistence)
      action_data = persistence.adapter.load_action(execution_plan_id, action_id)
      @subkeys.reduce(action_data[:output]) { |v, k| v.fetch k }
    end

    protected

    def self.new_from_hash(hash)
      check_class_matching hash
      new(hash.fetch(:execution_plan_id),
          hash.fetch(:step_id),
          hash.fetch(:action_id),
          hash.fetch(:subkeys))
    end

  end
end
