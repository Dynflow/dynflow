module Dynflow
  class ExecutionPlan::OutputReference < Serializable

    attr_reader :step_id, :action_id, :subkeys

    def initialize(step_id, action_id, subkeys = [])
      @step_id   = step_id
      @action_id = action_id
      @subkeys   = subkeys
    end

    def [](subkey)
      return self.class.new(step_id, action_id, subkeys.dup << subkey)
    end

    def to_hash
      { class:     self.class.to_s,
        step_id:   step_id,
        action_id: action_id,
        subkeys:   subkeys }
    end

    def inspect
      "Step(#{@step_id}).output".tap do |ret|
        ret << @subkeys.map { |k| "[:#{k}]" }.join('') if @subkeys.any?
      end
    end

    def dereference(persistence, execution_plan_id)
      action_data = persistence.adapter.load_action(execution_plan_id, action_id)
      if action_data[:state].to_s != 'success'
        raise "Referenced action #{action_id} is in #{action_data.inspect} state." +
              "We can dereference only actions that finished successfully"
      end
      deref = action_data[:output]
      @subkeys.each do |subkey|
        if deref.respond_to?(:[])
          deref = deref[subkey]
        else
          raise "We were not able to dereference subkey #{@subkeys} from #{self.inspect}"
        end
      end
      return deref
    end

    protected

    def self.new_from_hash(hash)
      check_class_matching hash
      new(hash[:step_id], hash[:action_id], hash[:subkeys])
    end

  end
end
