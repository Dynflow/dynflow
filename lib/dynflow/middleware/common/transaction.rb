module Dynflow
  module Middleware::Common
    class Transaction < Middleware
      def plan_phase(execution_plan)
        rollback_on_error(execution_plan)
      end

      def finalize_phase(execution_plan)
        rollback_on_error(execution_plan)
      end

      private

      def rollback_on_error(execution_plan)
        execution_plan.world.transaction_adapter.transaction do
          pass(execution_plan)
          if execution_plan.error?
            execution_plan.world.transaction_adapter.rollback
          end
        end
      end
    end
  end
end
