module Dynflow
  module ExecutionPlan::Steps
    class PlanStep < Abstract
      attr_reader :children

      # @param [Array] children is a private API parameter
      def initialize(execution_plan_id,
          id,
          state,
          action_class,
          action_id,
          error,
          world,
          started_at = nil,
          ended_at = nil,
          execution_time = 0.0,
          real_time = 0.0,
          children = [])

        super execution_plan_id, id, state, action_class, action_id, error, world, started_at,
              ended_at, execution_time, real_time
        children.all? { |child| is_kind_of! child, Integer }
        @children = children
      end

      def phase
        :plan_phase
      end

      def to_hash
        super.merge recursive_to_hash(:children => children)
      end

      # @return [Action]
      def execute(execution_plan, trigger, *args)
        is_kind_of! execution_plan, ExecutionPlan
        attributes = { execution_plan_id: execution_plan.id,
                       id:                action_id,
                       state:             :pending,
                       plan_step_id:      self.id }
        action     = action_class.plan_phase.new(attributes, execution_plan, trigger)

        with_time_calculation do
          action.execute(*args)
        end

        execution_plan.update_meta_data execution_time
        self.state = action.state
        self.error = action.error

        persistence.save_action(self, action)
        return action
      end

      def self.new_from_hash(hash, execution_plan_id, world)
        check_class_matching hash
        new execution_plan_id,
            hash[:id],
            hash[:state],
            Action.constantize(hash[:action_class]),
            hash[:action_id],
            hash_to_error(hash[:error]),
            world,
            string_to_time(hash[:started_at]),
            string_to_time(hash[:ended_at]),
            hash[:execution_time],
            hash[:real_time],
            hash[:children]
      end
    end
  end
end
