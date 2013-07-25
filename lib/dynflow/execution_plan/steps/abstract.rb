module Dynflow
  module ExecutionPlan::Steps
    class Abstract < Serializable
      include Algebrick::TypeCheck

      def self.new_from_hash(execution_plan, hash)
        raise ArgumentError unless hash[:class] == self.to_s
        new(execution_plan, *hash.values_at(:id, :state, :action_class, :action_id))
      end

      attr_reader :execution_plan, :id, :state, :action_class, :action_id

      def initialize(execution_plan, id, state, action_class, action_id)
        @id             = id || raise(ArgumentError, 'missing id')
        @execution_plan = is_kind_of! execution_plan, ExecutionPlan
        self.state      = state
        @action_class   = is_kind_of! action_class, Class
        @action_id      = action_id || raise(ArgumentError, 'missing action_id')
      end

      def persistence_adapter
        execution_plan.world.persistence_adapter
      end

      STATES = [:pending, :success, :suspended, :skipped, :error]

      def state=(state)
        raise "unknown state #{state}" unless STATES.include? state
        @state = state
      end

      def execute(*args)
        raise NotImplementedError
      end

      def to_hash
        { id:           id,
          state:        state,
          class:        self.class.to_s,
          action_class: action_class,
          action_id:    action_id }
      end
    end
  end
end
