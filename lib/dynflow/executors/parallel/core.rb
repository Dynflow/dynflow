module Dynflow
  module Executors
    class Parallel < Abstract

      # TODO implement graceful shutdown
      # TODO add dynflow error handling to avoid stucking and report errors to the future
      class Core < MicroActor
        def initialize(world, pool_size)
          super()
          @world                   = is_kind_of! world, World
          @pool                    = Pool.new(self, pool_size)
          @execution_plan_managers = {}
          # TODO load and start persisted execution plans in running state on core start
        end

        private

        def on_message(message)
          match message,
                Execution.(~any, ~any) >>-> execution_plan_id, future do
                  if (manager = track_execution_plan(execution_plan_id, future))
                    start_executing(manager)
                  end
                end,
                ~Resumption >>-> resumption do
                  resume(resumption)
                end,
                PoolDone.(~any) >>-> step do
                  update_manager(step)
                end
        end

        # @return false on problem
        def track_execution_plan(execution_plan_id, future)
          execution_plan = @world.persistence.load_execution_plan(execution_plan_id)

          if @execution_plan_managers[execution_plan_id]
            future.set error("cannot execute execution_plan_id:#{execution_plan_id} " +
                                 "it's already running")
            return false
          end

          if execution_plan.state == :stopped
            future.set error("cannot execute execution_plan_id:#{execution_plan_id} " +
                                 "it's stopped")
            return false
          end

          @execution_plan_managers[execution_plan_id] =
              ExecutionPlanManager.new(@world, execution_plan, future)
        end

        def error(message)
          StandardError.new(message).tap { |e| e.set_backtrace caller(1) }
        end

        def start_executing(manager)
          next_work = manager.start
          continue_manager manager, next_work
        end

        def update_manager(finished_work)
          manager   = @execution_plan_managers[finished_work.execution_plan_id]
          next_work = manager.what_is_next(finished_work)
          continue_manager manager, next_work
        end

        def continue_manager(manager, next_work)
          if manager.done?
            loose_manager_and_set_future manager.execution_plan.id
          else
            feed_pool next_work
          end
        end

        def feed_pool(work_items)
          work_items.all? { |w| is_kind_of! w, Work }
          work_items.each { |new_work| @pool << new_work }
        end

        def loose_manager_and_set_future(execution_plan_id)
          manager = @execution_plan_managers.delete(execution_plan_id)
          manager.future.set manager.execution_plan
        end

        def resume(resumption)
          if execution_plan_manager = @execution_plan_managers[resumption[:execution_plan_id]]
            @pool << execution_plan_manager.resume(resumption)
          else
            # TODO should be fixed when EP execution is resumed after restart
            raise "Trying to resume #{resumption[:execution_plan_id]}-#{resumption[:step_id]} failed, " +
                      'missing manager.'
          end
        end
      end
    end
  end
end
