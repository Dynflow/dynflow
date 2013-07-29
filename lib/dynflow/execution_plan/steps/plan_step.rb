module Dynflow
  module ExecutionPlan::Steps
    class PlanStep < Abstract
      attr_reader :children

      def to_hash
        super.merge(:children => children)
      end

      # @param [Array] children is a private API parameter
      def initialize(execution_plan, id, state, action_class, action_id, children = [])
        super execution_plan, id, state, action_class, action_id
        children.all? { |child| is_kind_of! child, Integer }
        @children = children
      end

      # @return [Action]
      def execute(trigger, *args)
        attributes = { id: action_id, state: :pending, plan_step_id: self.id }
        action     = action_class.plan_phase.new(attributes, execution_plan, trigger)

        action.execute(*args)
        self.state = action.state

        persistence_adapter.save_action(execution_plan.id, action_id, action.to_hash)
        return action
      end

      def self.new_from_hash(hash, execution_plan)
        check_class_matching hash
        #noinspection RubyArgCount
        new execution_plan,
            hash[:id],
            hash[:state],
            hash[:action_class].constantize,
            hash[:action_id],
            hash[:children]
      end
    end
  end
end
