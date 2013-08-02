module Dynflow
  module Executors
    class Parallel < Abstract
      class Core < MicroActor
        def initialize(world, pool_size)
          super()
          @world                   = is_kind_of! world, World
          @pool                    = Pool.new(self, pool_size)
          @execution_plan_managers = {}
        end

        private

        def on_message(message)
          match message,
                Execute.(~any, ~any) --> execution_plan_id, future do
                  manager = track_execution_plan execution_plan_id, future
                  start_executing manager
                end,
                PoolDone.(~any) --> step do
                  update_manager step
                end
        end

        def track_execution_plan(execution_plan_id, future)
          execution_plan                              = @world.persistence.load_execution_plan(execution_plan_id)
          @execution_plan_managers[execution_plan_id] = ExecutionPlanManager.new(execution_plan, future)
        end

        def start_executing(manager)
          manager.start.each { |step| @pool << Work[step] }
        end

        def update_manager(finished_step)
          manager = @execution_plan_managers[finished_step.execution_plan_id]
          manager.what_is_next(finished_step).each { |new_step| @pool << Work[new_step] }
          @execution_plan_managers.delete(finished_step.execution_plan_id) if manager.done?
        end
      end
    end
  end
end
