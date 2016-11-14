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
                     started_at     = nil,
                     ended_at       = nil,
                     execution_time = 0.0,
                     real_time      = 0.0,
                     children       = [])

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

      def delay(delay_options, args)
        @action.execute_delay(delay_options, *args)
        persistence.save_action(execution_plan_id, @action)
        @action.serializer
      ensure
        save
      end

      # @return [Action]
      def execute(execution_plan, trigger, from_subscription, *args)
        unless @action
          raise "The action was not initialized, you might forgot to call initialize_action method"
        end
        @action.set_plan_context(execution_plan, trigger, from_subscription)
        Type! execution_plan, ExecutionPlan
        with_meta_calculation(@action) do
          @action.execute(*args)
        end

        persistence.save_action(execution_plan_id, @action)
        return @action
      end

      def self.state_transitions
        @state_transitions ||= { scheduling: [:pending, :error],
                                 pending:    [:running, :error],
                                 running:    [:success, :error],
                                 success:    [],
                                 suspended:  [],
                                 skipped:    [],
                                 error:      [] }
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

      def load_action
        @action = @world.persistence.load_action(self)
      end

      def initialize_action(caller_action = nil)
        attributes = { execution_plan_id: execution_plan_id,
                       id:                action_id,
                       step:              self,
                       plan_step_id:      self.id,
                       run_step_id:       nil,
                       finalize_step_id:  nil,
                       phase:             phase }
        if caller_action
          attributes.update(caller_execution_plan_id: caller_action.execution_plan_id,
                            caller_action_id:         caller_action.id)
        end
        @action = action_class.new(attributes, world)
        persistence.save_action(execution_plan_id, @action)
        @action
      end
    end
  end
end
