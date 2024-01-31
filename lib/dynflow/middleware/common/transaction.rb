# frozen_string_literal: true

module Dynflow
  module Middleware::Common
    class Transaction < Middleware
      def plan_phase(execution_plan, **kwargs)
        rollback_on_error(execution_plan, **kwargs)
      end

      def finalize_phase(execution_plan, **kwargs)
        rollback_on_error(execution_plan, **kwargs)
      end

      private

      def rollback_on_error(execution_plan, **kwargs)
        execution_plan.world.transaction_adapter.transaction do
          pass(execution_plan, **kwargs)
          if execution_plan.error?
            execution_plan.world.transaction_adapter.rollback
          end
        end
      end
    end
  end
end
