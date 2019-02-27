module Dynflow
  # Director is responsible for telling what to do next when:
  #   * new execution starts
  #   * an event accurs
  #   * some work is finished
  #
  # It's public methods (except terminate) return work items that the
  # executor should understand
  class Director
    include Algebrick::TypeCheck

    Event = Algebrick.type do
      fields! execution_plan_id: String,
              step_id:           Integer,
              event:             Object,
              result:            Concurrent::Promises::ResolvableFuture
    end

    UnprocessableEvent = Class.new(Dynflow::Error)

    class WorkItem
      attr_reader :execution_plan_id, :queue

      def initialize(execution_plan_id, queue)
        @execution_plan_id = execution_plan_id
        @queue = queue
      end

      def execute
        raise NotImplementedError
      end
    end

    class StepWorkItem < WorkItem
      attr_reader :step

      def initialize(execution_plan_id, step, queue)
        super(execution_plan_id, queue)
        @step = step
      end

      def execute
        @step.execute(nil)
      end
    end

    class EventWorkItem < StepWorkItem
      attr_reader :event

      def initialize(execution_plan_id, step, event, queue)
        super(execution_plan_id, step, queue)
        @event = event
      end

      def execute
        @step.execute(@event.event)
      end
    end

    class FinalizeWorkItem < WorkItem
      def initialize(execution_plan_id, sequential_manager, queue)
        super(execution_plan_id, queue)
        @sequential_manager = sequential_manager
      end

      def execute
        @sequential_manager.finalize
      end
    end

    require 'dynflow/director/work_queue'
    require 'dynflow/director/sequence_cursor'
    require 'dynflow/director/flow_manager'
    require 'dynflow/director/execution_plan_manager'
    require 'dynflow/director/sequential_manager'
    require 'dynflow/director/running_steps_manager'

    attr_reader :logger

    def initialize(world)
      @world = world
      @logger = world.logger
      @execution_plan_managers = {}
      @rescued_steps = {}
    end

    def current_execution_plan_ids
      @execution_plan_managers.keys
    end

    def start_execution(execution_plan_id, finished)
      manager = track_execution_plan(execution_plan_id, finished)
      return [] unless manager
      unless_done(manager, manager.start)
    end

    def handle_event(event)
      Type! event, Event
      execution_plan_manager = @execution_plan_managers[event.execution_plan_id]
      if execution_plan_manager
        execution_plan_manager.event(event)
      else
        raise Dynflow::Error, "no manager for #{event.inspect}"
      end
    rescue Dynflow::Error => e
      event.result.reject e.message
      raise e
    end

    def work_finished(work)
      manager = @execution_plan_managers[work.execution_plan_id]
      unless_done(manager, manager.what_is_next(work))
    end

    # called when there was an unhandled exception during the execution
    # of the work (such as persistence issue) - in this case we just clean up the
    # runtime from the execution plan and let it go (common cause for this is the execution
    # plan being removed from database by external user)
    def work_failed(work)
      if (manager = @execution_plan_managers[work.execution_plan_id])
        manager.terminate
        # Don't try to store when the execution plan went missing
        plan_missing = @world.persistence.find_execution_plans(:filters => { uuid: work.execution_plan_id }).empty?
        finish_manager(manager, store: !plan_missing)
      end
    end

    def terminate
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
          finish_manager(manager)
        end
      end
    end

    private

    def unless_done(manager, work_items)
      return [] unless manager
      if manager.done?
        try_to_rescue(manager) || finish_manager(manager)
      else
        return work_items
      end
    end

    def try_to_rescue(manager)
      rescue!(manager) if rescue?(manager)
    end

    def finish_manager(manager, store: true)
      update_execution_plan_state(manager) if store
      return []
    ensure
      @execution_plan_managers.delete(manager.execution_plan.id)
      set_future(manager)
    end

    def rescue?(manager)
      if @world.terminating? || !(@world.auto_rescue && manager.execution_plan.error?)
        false
      elsif !@rescued_steps.key?(manager.execution_plan.id)
        # we have not rescued this plan yet
        true
      else
        # we have rescued this plan already, but a different step has failed now
        # we do this check to prevent endless loop, if we always failed on the same steps
        failed_step_ids = manager.execution_plan.failed_steps.map(&:id).to_set
        (failed_step_ids - @rescued_steps[manager.execution_plan.id]).any?
      end
    end

    def rescue!(manager)
      # TODO: after moving to concurrent-ruby actors, there should be better place
      # to put this logic of making sure we don't run rescues in endless loop
      @rescued_steps[manager.execution_plan.id] ||= Set.new
      @rescued_steps[manager.execution_plan.id].merge(manager.execution_plan.failed_steps.map(&:id))
      new_state = manager.execution_plan.prepare_for_rescue
      if new_state == :running
        return manager.restart
      else
        manager.execution_plan.state = new_state
        return false
      end
    end

    def track_execution_plan(execution_plan_id, finished)
      execution_plan = @world.persistence.load_execution_plan(execution_plan_id)

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
      finished.reject e
      nil
    end

    def update_execution_plan_state(manager)
      execution_plan = manager.execution_plan
      case execution_plan.state
      when :running
        if execution_plan.error?
          execution_plan.execution_history.add('pause execution', @world.id)
          execution_plan.update_state(:paused)
        elsif manager.done?
          execution_plan.execution_history.add('finish execution', @world.id)
          execution_plan.update_state(:stopped)
        end
        # If the state is marked as running without errors but manager is not done,
        # we let the invalidation procedure to handle re-execution on other executor
      when :paused
        execution_plan.execution_history.add('pause execution', @world.id)
        execution_plan.save
      when :stopped
        execution_plan.execution_history.add('finish execution', @world.id)
        execution_plan.save
      end
    end

    def set_future(manager)
      @rescued_steps.delete(manager.execution_plan.id)
      manager.future.fulfill manager.execution_plan
    end
  end
end
