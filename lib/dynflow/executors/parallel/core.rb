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
          @pool                    = Pool.new(self, pool_size, world.transaction_adapter)
          @execution_plan_managers = {}
        end

        def on_message(message)
          match message,
                (on ~Execution do |(execution_plan_id, finished)|
                  start_executing track_execution_plan(execution_plan_id, finished)
                  true
                end),
                (on ~Event do |event|
                  event(event)
                end),
                (on PoolDone.(~any) do |step|
                  update_manager(step)
                end)
        end

        def termination
          logger.info 'shutting down Core ...'
          try_to_terminate
        end

        # @return false on problem
        def track_execution_plan(execution_plan_id, finished)
          execution_plan = @world.persistence.load_execution_plan(execution_plan_id)

          if terminating?
            raise Dynflow::Error,
                  "cannot accept execution_plan_id:#{execution_plan_id} core is terminating"
          end

          if @execution_plan_managers[execution_plan_id]
            raise Dynflow::Error,
                  "cannot execute execution_plan_id:#{execution_plan_id} it's already running"
          end

          if execution_plan.state == :stopped
            raise Dynflow::Error,
                  "cannot execute execution_plan_id:#{execution_plan_id} it's stopped"
          end

          @execution_plan_managers[execution_plan_id] =
              ExecutionPlanManager.new(@world, execution_plan, finished)

        rescue Dynflow::Error => e
          finished.fail e
          raise e
        end

        def start_executing(manager)
          Type! manager, ExecutionPlanManager

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
            logger.warn format('dropping event %s - no manager for %s:%s',
                               event, event.execution_plan_id, event.step_id)
            event.result.fail UnprocessableEvent.new(
                                  "no manager for #{event.execution_plan_id}:#{event.step_id}")
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
