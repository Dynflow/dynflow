module Dynflow
  module Executors
    class Parallel < Abstract

      # TODO add dynflow error handling to avoid getting stuck and report errors to the future
      class Core < MicroActor
        def initialize(world, pool_size)
          super(world.logger, world, pool_size)
        end

        private

        def delayed_initialize(world, pool_size)
          @world                   = Type! world, World
          @pool                    = Pool.new(self, pool_size)
          @execution_plan_managers = {}

          @world.initialized.wait

          abnormal_execution_plans = @world.persistence.find_execution_plans filters: { 'state' => %w(running planning) }
          if abnormal_execution_plans.empty?
            logger.info 'Clean start.'
          else
            format_str = '%36s %10s %10s'
            message    = ['Abnormal execution plans, process was probably killed.',
                          'Following ExecutionPlans will be set to paused, admin has to fix them manually.',
                          (format format_str, 'ExecutionPlan', 'state', 'result'),
                          *(abnormal_execution_plans.map { |ep| format format_str, ep.id, ep.state, ep.result })]

            logger.error message.join("\n")

            abnormal_execution_plans.each do |ep|
              ep.update_state case ep.state
                              when :planning
                                :stopped
                              when :running
                                :paused
                              else
                                raise
                              end
            end
          end

          # TODO after kill:
          # - TODO recalculate incrementally all running-EPs meta data
          # - TODO detect steps stuck in running phase, what to do?
        end

        def on_message(message)
          match message,
                Execution.(~any, ~any, ~any) >-> execution_plan_id, accepted, finished do
                  if (manager = track_execution_plan(execution_plan_id, accepted, finished))
                    start_executing(manager)
                  end
                end,
                ~Event >-> event do
                  event(event)
                end,
                PoolDone.(~any) >-> step do
                  update_manager(step)
                end
        end

        def termination
          logger.info 'shutting down Core ...'
          try_to_terminate
        end

        # @return false on problem
        def track_execution_plan(execution_plan_id, accepted, finished)
          execution_plan = @world.persistence.load_execution_plan(execution_plan_id)

          if terminating?
            accepted.resolve error("cannot accept execution_plan_id:#{execution_plan_id} " +
                                       'core is terminating')
            return false
          end

          if @execution_plan_managers[execution_plan_id]
            accepted.resolve error("cannot execute execution_plan_id:#{execution_plan_id} " +
                                       "it's already running")
            return false
          end

          if execution_plan.state == :stopped
            accepted.resolve error("cannot execute execution_plan_id:#{execution_plan_id} " +
                                       "it's stopped")
            return false
          end

          accepted.resolve true
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
            try_to_terminate
          else
            feed_pool next_work
          end
        end

        def feed_pool(work_items)
          Type! work_items, Array, Work, NilClass
          return if work_items.nil?
          work_items = [work_items] if work_items.is_a? Work
          work_items.all? { |i| Type! i, Work }
          work_items.each { |new_work| @pool << new_work }
        end

        def loose_manager_and_set_future(execution_plan_id)
          manager = @execution_plan_managers.delete(execution_plan_id)
          manager.future.resolve manager.execution_plan
        end

        def event(event)
          Type! event, Event
          execution_plan_manager = @execution_plan_managers[event.execution_plan_id]
          if execution_plan_manager
            feed_pool execution_plan_manager.event(event)
            true
          else
            logger.warn "dropping event #{event} - no manager for #{event.execution_plan_id}:#{event.step_id}"
            event.result.fail UnprocessableEvent.new("no manager for #{event.execution_plan_id}:#{event.step_id}")
          end
        end

        def try_to_terminate
          if terminating? && @execution_plan_managers.empty?
            @pool.ask(Terminate).wait
            logger.info '... Core terminated.'
            terminate!
          end
        end
      end
    end
  end
end
