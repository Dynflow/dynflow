module Dynflow
  module Executors
    class Parallel < Abstract

      # TODO add dynflow error handling to avoid stucking and report errors to the future
      class Core < MicroActor
        def initialize(world, pool_size)
          super(world.logger)
          @world                   = is_kind_of! world, World
          @pool                    = Pool.new(self, pool_size)
          @execution_plan_managers = {}
          @termination_future      = nil

          # TODO after restart/kill procedure:
          #   - TODO recalculate incrementally all running-EPs meta data
          #   - TODO set all running EPs as paused for admin to resume manually
          #   - TODO detect steps stuck in running phase
        end

        def terminating?
          !!@termination_future
        end

        private

        def on_message(message)
          match message,
                Execution.(~any, ~any, ~any) >-> execution_plan_id, accepted, finished do
                  if (manager = track_execution_plan(execution_plan_id, accepted, finished))
                    start_executing(manager)
                  end
                end,
                ~ProgressUpdate >-> progress_update do
                  update_progress(progress_update)
                end,
                PoolDone.(~any) >-> step do
                  update_manager(step)
                end,
                Terminate.(~any) >-> future do
                  logger.info 'shutting down Core ...'
                  @termination_future = future
                end
        end

        # @return false on problem
        def track_execution_plan(execution_plan_id, accepted, finished)
          execution_plan = @world.persistence.load_execution_plan(execution_plan_id)

          if terminating?
            accepted.set error("cannot accept execution_plan_id:#{execution_plan_id} " +
                                   'core is terminating')
            return false
          end

          if @execution_plan_managers[execution_plan_id]
            accepted.set error("cannot execute execution_plan_id:#{execution_plan_id} " +
                                   "it's already running")
            return false
          end

          if execution_plan.state == :stopped
            accepted.set error("cannot execute execution_plan_id:#{execution_plan_id} " +
                                   "it's stopped")
            return false
          end

          accepted.set true
          @execution_plan_managers[execution_plan_id] =
              ExecutionPlanManager.new(@world, execution_plan, finished)
        end

        def error(message)
          Dynflow::Error.new(message) #.tap { |e| e.set_backtrace caller(1) }
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
            terminate! if terminating? && @execution_plan_managers.empty?
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

        def terminate!
          @pool << Terminate[pool_terminated = Future.new]
          pool_terminated.wait
          @termination_future.set true
          super()
        end
      end
    end
  end
end
