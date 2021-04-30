# frozen_string_literal: true
module Dynflow
  module ExecutionPlan::Steps
    class AbstractFlowStep < Abstract

      # Method called when initializing the step to customize the behavior based on the
      # action definition during the planning phase
      def update_from_action(action)
        @queue = action.queue
        @queue ||= action.triggering_action.queue if action.triggering_action
        @queue ||= :default
      end

      def execute(*args)
        return self if [:skipped, :success].include? self.state
        open_action do |action|
          with_meta_calculation(action) do
            action.execute(*args)
            @delayed_events = action.delayed_events
          end
        end
      end

      def clone
        self.class.from_hash(to_hash, execution_plan_id, world)
      end

      private

      def open_action
        action = persistence.load_action(self)
        yield action
        persistence.save_action(execution_plan_id, action)
        persistence.save_output_chunks(execution_plan_id, action.id, action.pending_output_chunks)
        save

        return self
      end
    end
  end
end
