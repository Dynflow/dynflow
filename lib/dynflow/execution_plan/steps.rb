module Dynflow
  module ExecutionPlan::Steps
    class Abstract < Serializable
      def self.new_from_hash(execution_plan, hash)
        raise ArgumentError unless hash[:class] == self.to_s
        new execution_plan, *hash.values_at(:id, :state, :action_class, :action_id)
      end

      attr_reader :execution_plan, :id, :state, :action_class, :action_id

      def initialize(execution_plan, id, state, action_class, action_id)
        @id             = id
        @execution_plan = execution_plan
        self.state      = state
        @action_class   = action_class
        @action_id      = action_id
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

    class Planning < Abstract
      attr_reader :children

      def initialize(execution_plan, id, state, action_class, action_id)
        super execution_plan, id, state, action_class, action_id
        @children = []
      end

      def execute(trigger, *args)
        action = action_class.planning.
            new(execution_plan.world, :pending, action_id, execution_plan, trigger).
            execute(*args)
        persistence_adapter.save_action execution_plan.id, action_id, action.to_hash
      end
    end

    class Running < Abstract
      def execute

      end
    end
  end
end
