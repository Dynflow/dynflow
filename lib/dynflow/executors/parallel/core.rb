module Dynflow
  module Executors
    class Parallel < Abstract

      # TODO make sure there is only one core running (cross-process)
      # TODO implement shutdown
      #   - soft: wait for all EPs to finish
      #   - hard: wait only for steps
      # TODO add dynflow error handling to avoid stucking and report errors to the future
      class Core < MicroActor
        def initialize(world, pool_size)
          super()
          @world                   = is_kind_of! world, World
          @pool                    = Pool.new(self, pool_size)
          @execution_plan_managers = {}
          # TODO after restart procedure:
          #   - TODO recalculate incrementally all running-EPs meta data
          #   - TODO set all running EPs as paused for admin to resume manually
          #   - TODO detect steps stuck in running phase
        end

        private

        def on_message(message)
          match message,
                Execution.(~any, ~any) >>-> execution_plan_id, future do
                  if (manager = track_execution_plan(execution_plan_id, future))
                    start_executing(manager)
                  end
                end,
                ~ProgressUpdate >>-> progress_update do
                  update_progress(progress_update)
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

        def update_progress(progress_update)
          if execution_plan_manager = @execution_plan_managers[progress_update.execution_plan_id]
            feed_pool [execution_plan_manager.update_progress(progress_update)]
          else
            # TODO should be fixed when EP execution is resumed after restart
            raise "Trying to resume execution_plan:#{progress_update.execution_plan_id} step:#{progress_update.step_id} failed, " +
                      'missing manager.'
          end
        end
      end
    end
  end
end
