module Dynflow
  module Executors
    class Parallel < Abstract
      class Manager
        include Algebrick::TypeCheck

        attr_reader :execution_plan

        def initialize(execution_plan, future)
          @execution_plan = is_kind_of! execution_plan, ExecutionPlan
          @future         = is_kind_of! future, Future

          run_manager = FlowManager.new(execution_plan, execution_plan.run_flow) unless execution_plan.run_flow.empty?
          finalize_manager = FlowManager.new(execution_plan, execution_plan.finalize_flow) unless execution_plan.finalize_flow.empty?
          @flow_managers = [run_manager, finalize_manager].compact
          @iteration     = 0
        end

        def start
          current_manager.start
        end

        # @return [Set] of step_ids to continue with
        def done_give_me_next(flow_step)
          next_steps = current_manager.done_give_me_next(flow_step)

          if current_manager.done?
            raise 'invalid state' unless next_steps.empty?
            if next_manager?
              next_manager!
              return start
            else
              @future.set @execution_plan
            end
          end

          return next_steps
        end

        def done?
          @flow_managers.all?(&:done?)
        end

        private

        def current_manager
          @flow_managers[@iteration]
        end

        def next_manager?
          @iteration < @flow_managers.size-1
        end

        def next_manager!
          @iteration += 1
        end

      end
    end
  end
end
