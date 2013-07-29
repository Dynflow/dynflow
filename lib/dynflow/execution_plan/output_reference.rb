module Dynflow
  class ExecutionPlan::OutputReference < Serializable

    attr_reader :step_id, :subkeys

    def initialize(step_id, subkeys = [])
      @step_id = step_id
      @subkeys = subkeys
    end

    def [](subkey)
      return self.class.new(step_id, subkeys.dup << subkey)
    end

    def to_hash
      { class:   self.class.to_s,
        step_id: step_id,
        subkeys: subkeys }
    end

    def inspect
      "Step(#{@step_id}).output".tap do |ret|
        ret << @subkeys.map { |k| "[#{k}]" }.join('') if @subkeys.any?
      end
    end

    protected

    def self.new_from_hash(hash)
      check_class_matching hash
      new(hash['step_id'], hash['subkeys'])
    end

  end
end
