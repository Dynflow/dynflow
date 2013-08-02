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
          match(message,
                Execute.(~any, ~any) --> execution_plan_id, future do
                  if manager = track_execution_plan(execution_plan_id, future)
                    start_executing(manager)
                  end
                end,
                PoolDone.(~any) --> step do
                  update_manager(step)
                end)
        end

        def track_execution_plan(execution_plan_id, future)
          execution_plan = @world.persistence.load_execution_plan(execution_plan_id)
          manager        = ExecutionPlanManager.new(@world, execution_plan, future)
          unless future.ready?
            @execution_plan_managers[execution_plan_id] = manager
          end
        end

        def start_executing(manager)
          manager.start.each { |work| @pool << work }
        end

        def update_manager(finished_work)
          manager   = @execution_plan_managers[finished_work.execution_plan_id]
          next_work = manager.what_is_next(finished_work)
          next_work.all? { |w| is_kind_of! w, Work }
          next_work.each { |new_work| @pool << new_work }
          @execution_plan_managers.delete(finished_work.execution_plan_id) if manager.done?
        end
      end
    end
  end
end
