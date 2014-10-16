module Dynflow
  module Executors
    class Parallel < Abstract

      # TODO add dynflow error handling to avoid getting stuck and report errors to the future
      class Core < Concurrent::Actor::Context
        include Algebrick::Matching
        attr_reader :logger

        StartTerminating = Algebrick.type do
          fields! terminated: Concurrent::IVar
        end

        def initialize(world, pool_size)
          @logger                  = world.logger
          @world                   = Type! world, World
          @pool                    = Pool.spawn('pool', reference, pool_size, world.transaction_adapter)
          @execution_plan_managers = {}
          @plan_ids_in_rescue      = Set.new
          @terminated              = nil
        end

        def on_message(message)
          match message,
                (on ~Parallel::Execution do |(execution_plan_id, finished)|
                  start_executing track_execution_plan(execution_plan_id, finished)
                  true
                end),
                (on ~Parallel::Event do |event|
                  event(event)
                end),
                (on PoolDone.(~any) do |step|
                  update_manager(step)
                end),
                (on StartTerminating.(~any) do |terminated|
                  logger.info 'shutting down Core ...'
                  @terminated = terminated
                  try_to_terminate
                end)
        end

        # @return
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
          nil
        end

        def terminating?
          !!@terminated
        end

        def start_executing(manager)
          return if manager.nil?
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
            finish_plan manager.execution_plan.id
          else
            feed_pool next_work
          end
        ensure
          try_to_terminate(manager)
        end

        def rescue?(manager)
          return false if terminating?
          @world.auto_rescue && manager.execution_plan.state == :paused &&
              !@plan_ids_in_rescue.include?(manager.execution_plan.id)
        end

        def rescue!(manager)
          # TODO: after moving to concurrent-ruby actors, there should be better place
          # to put this logic of making sure we don't run rescues in endless loop
          @plan_ids_in_rescue << manager.execution_plan.id
          rescue_plan_id = manager.execution_plan.rescue_plan_id
          if rescue_plan_id
            self << Parallel::Execution[rescue_plan_id, manager.future]
          else
            set_future(manager)
          end
        end

        def feed_pool(work_items)
          return if terminating?
          Type! work_items, Array, Work, NilClass
          return if work_items.nil?
          work_items = [work_items] if work_items.is_a? Work
          work_items.all? { |i| Type! i, Work }
          work_items.each { |new_work| @pool << new_work }
        end

        def finish_plan(execution_plan_id)
          manager = @execution_plan_managers.delete(execution_plan_id)
          if rescue?(manager)
            rescue!(manager)
          else
            set_future(manager)
          end
        end

        def terminate_managers!
          @execution_plan_managers.delete_if do |_, manager|
            if manager.try_to_terminate
              set_future(manager)
              true
            end
          end
        end

        def set_future(manager)
          @plan_ids_in_rescue.delete(manager.execution_plan.id)
          manager.future.set manager.execution_plan
        end


        def event(event)
          Type! event, Parallel::Event
          execution_plan_manager = @execution_plan_managers[event.execution_plan_id]
          if execution_plan_manager
            feed_pool execution_plan_manager.event(event)
            true
          else
            logger.warn format('dropping event %s - no manager for %s:%s',
                               event, event.execution_plan_id, event.step_id)
            eventh.result.fail UnprocessableEvent.new(
                                  "no manager for #{event.execution_plan_id}:#{event.step_id}")
          end
        end

        def try_to_terminate(manager = nil)
          return unless terminating?
          terminate_managers!
          if @execution_plan_managers.empty?
            @pool.ask(:terminate!).wait
            reference.ask :terminate!
            logger.info '... Core terminated.'
            @terminated.set true
          end
        end
      end
    end
  end
end
