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
        @id = id or raise ArgumentError, 'missing id'
        @execution_plan = is_kind_of! execution_plan, ExecutionPlan
        self.state      = state
        @action_class   = is_kind_of! action_class, Class
        @action_id = action_id or raise ArgumentError, 'missing action_id'
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

      # @return [Action]
      def execute(trigger, *args)
        action = action_class.planning.
          new(execution_plan.world, :pending, action_id, execution_plan, self.id, trigger)

        action.execute(*args)
        persistence_adapter.save_action(execution_plan.id, action_id, action.to_hash)
        return action
      end
    end

    class Running < Abstract

      def action
        action_hash = persistence_adapter.load_action(execution_plan.id, action_id)
        # TODO: dereference if possible
        Action.running.new_from_hash(execution_plan.world,
                                     state,
                                     action_id,
                                     action_hash)
      end

      def execute
      end
    end

    class OutputReference < Serializable

      attr_reader :step_id, :subkeys

      def initialize(step_id, subkeys = [])
        @step_id = step_id
        @subkeys = subkeys
      end

      def [](subkey)
        return self.class.new(step_id, subkeys.dup << subkey)
      end

      def to_hash
        {
          'step_id' => step_id,
          'subkeys' => subkeys
        }
      end

      def self.new_from_hash(hash)
        self.new(hash['step_id'], hash['subkeys'])
      end

      def inspect
        "Step(#{@step_id}).output".tap do |ret|
          ret << @subkeys.map { |k| "[#{k}]" }.join('') if @subkeys.any?
        end
      end

    end


    class DependencyGraph

      def initialize
        @graph = Hash.new { |h, k| h[k] = Set.new }
      end

      # adds dependencies to graph that +step+ has based
      # on the steps referenced in its +input+
      def add_dependencies(step, input)
        required_step_ids = extract_required_step_ids(input)
        required_step_ids.each do |required_step_id|
          @graph[step.id] << required_step_id
        end
      end

      def required_step_ids(step_id)
        @graph[step_id]
      end

      def mark_satisfied(step_id, required_step_id)
        @graph[step_id].delete(required_step_id)
      end

      def unresolved?
        @graph.any? { |step_id, required_step_ids| required_step_ids.any? }
      end

      private

      # @return [Array<Fixnum>] - ids of steps referenced from args
      def extract_required_step_ids(value)
        ret = case value
              when Hash
                value.values.map { |val| extract_required_step_ids(val) }
              when Array
                value.map { |val| extract_required_step_ids(val) }
              when ExecutionPlan::Steps::OutputReference
                value.step_id
              else
                # no reference hidden in this arg
              end
        return Array(ret).flatten.compact
      end




    end

  end
end
