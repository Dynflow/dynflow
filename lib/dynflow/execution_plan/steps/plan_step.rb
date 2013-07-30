module Dynflow
  module ExecutionPlan::Steps
    class PlanStep < Abstract
      attr_reader :children

      # @param [Array] children is a private API parameter
      def initialize(execution_plan_id, id, state, action_class, action_id, world, children = [])
        super execution_plan_id, id, state, action_class, action_id, world
        children.all? { |child| is_kind_of! child, Integer }
        @children = children
      end

      def phase
        :plan_phase
      end

      def to_hash
        super.merge(:children => children)
      end

      # @return [Action]
      def execute(execution_plan, trigger, *args)
        is_kind_of! execution_plan, ExecutionPlan
        attributes = { id: action_id, state: :pending, plan_step_id: self.id }
        action     = action_class.plan_phase.new(attributes, execution_plan, trigger)

        action.execute(*args)
        self.state = action.state

        persistence.save_action(self, action)
        return action
      end

      def self.new_from_hash(hash, execution_plan_id, world)
        check_class_matching hash
        new execution_plan_id,
            hash[:id],
            hash[:state],
            hash[:action_class].constantize,
            hash[:action_id],
            world,
            hash[:children]
      end
    end
  end
end
