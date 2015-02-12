module Dynflow
  module Executors
    class Parallel < Abstract

      class Core < Actor
        attr_reader :logger

        def initialize(world, pool_size)
          @logger                  = world.logger
          @world                   = Type! world, World
          @pool                    = Pool.spawn('pool', reference, pool_size, world.transaction_adapter)
          @execution_plan_managers = {}
          @plan_ids_in_rescue      = Set.new
          @terminated              = nil
        end

        def handle_execution(execution_plan_id, finished)
          start_executing track_execution_plan(execution_plan_id, finished)
        end

        def handle_event(event)
          Type! event, Parallel::Event
          if terminating?
            raise Dynflow::Error,
                  "cannot accept event: #{event} core is terminating"
          end
          execution_plan_manager = @execution_plan_managers[event.execution_plan_id]
          if execution_plan_manager
            feed_pool execution_plan_manager.event(event)
            true
          else
            raise Dynflow::Error, "no manager for #{event.execution_plan_id}:#{event.step_id}"
          end
        rescue Dynflow::Error => e
          event.result.fail e.message
          raise e
        end

        def finish_step(step)
          update_manager(step)
        end

        def handle_persistence_error(error)
          logger.fatal "PersistenceError in executor: terminating"
          logger.fatal error
          @world.terminate
        end

        def start_termination(*args)
          super
          logger.info 'shutting down Core ...'
          @pool.tell([:start_termination, Concurrent::IVar.new])
        end

        def finish_termination
          unless @execution_plan_managers.empty?
            logger.error "... cleaning #{@execution_plan_managers.size} execution plans ..."
            begin
              @execution_plan_managers.values.each do |manager|
                manager.terminate
              end
            rescue Errors::PersistenceError
              logger.error "could not to clean the data properly"
            end
            @execution_plan_managers.values.each do |manager|
              finish_plan(manager.execution_plan.id)
            end
          end
          logger.error '... core terminated.'
          super
        end

        private

        def on_message(message)
          super
        rescue Errors::PersistenceError => e
          self.tell(:handle_persistence_error, e)
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
            reference.tell([:handle_execution, rescue_plan_id, manager.future])
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
          work_items.each { |new_work| @pool.tell([:schedule_work, new_work]) }
        end

        def finish_plan(execution_plan_id)
          manager = @execution_plan_managers.delete(execution_plan_id)
          if rescue?(manager)
            rescue!(manager)
          else
            set_future(manager)
          end
        end

        def set_future(manager)
          @plan_ids_in_rescue.delete(manager.execution_plan.id)
          manager.future.set manager.execution_plan
        end

        def start_executing(manager)
          return if manager.nil?
          Type! manager, ExecutionPlanManager

          next_work = manager.start
          continue_manager manager, next_work
        end

      end
    end
  end
end
