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
        children.all? { |child| Type! child, Integer }
        @children = children
      end

      def planned_steps(execution_plan)
        @children.map { |id| execution_plan.steps.fetch(id) }
      end

      def phase
        Action::Plan
      end

      def to_hash
        super.merge recursive_to_hash(:children => children)
      end

      # @return [Action]
      def execute(execution_plan, trigger, *args)
        Type! execution_plan, ExecutionPlan
        attributes = { execution_plan_id: execution_plan.id,
                       id:                action_id,
                       step:              self,
                       plan_step_id:      self.id,
                       run_step_id:       nil,
                       finalize_step_id:  nil,
                       phase:             phase,
                       execution_plan:    execution_plan,
                       trigger:           trigger }
        action     = action_class.new(attributes, execution_plan.world)
        persistence.save_action(execution_plan_id, action)

        with_meta_calculation(action) do
          action.execute(*args)
        end

        execution_plan.update_execution_time execution_time

        persistence.save_action(execution_plan_id, action)
        return action
      end

      def self.state_transitions
        @state_transitions ||= { pending:   [:running],
                                 running:   [:success, :error],
                                 success:   [],
                                 suspended: [],
                                 skipped:   [],
                                 error:     [] }
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
