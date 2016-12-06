module Dynflow
  module ExecutionPlan::Steps
    class FinalizeStep < AbstractFlowStep

      def self.state_transitions
        @state_transitions ||= {
            pending:   [:running, :skipped, :reverted], # :skipped when its run_step is skipped
            running:   [:success, :error],
            success:   [:pending], # when restarting finalize phase
            suspended: [],
            skipped:   [],
            error:     [:pending, :skipped] # pending when restarting finalize phase
        }
      end

      def update_from_action(action)
        super
        self.progress_weight = action.finalize_progress_weight
      end

      def phase
        Action::Finalize
      end

      def mark_to_skip
        self.state = :skipped
        self.save
      end
    end

    class RevertPlanStep < FinalizeStep
      include Revert

      def real_execute(action, *args)
        action.send(:in_finalize_phase) do |action|
          world.middleware.execute(:revert_plan, action) do
            action.revert_plan
          end
        end
        reset_original_step!(action, 'plan')
        original_execution_plan(action).update_state(:stopped) if entry_action?(action)
      end
    end
  end
end
