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
              step_id:           Fixnum,
              event:             Object,
              result:            Concurrent::Edge::Future
    end

    UnprocessableEvent = Class.new(Dynflow::Error)

    class WorkItem
      attr_reader :execution_plan_id

      def initialize(execution_plan_id)
        @execution_plan_id = execution_plan_id
      end

      def execute
        raise NotImplementedError
      end
    end

    class StepWorkItem < WorkItem
      attr_reader :step

      def initialize(execution_plan_id, step)
        super(execution_plan_id)
        @step = step
      end

      def execute
        @step.execute(nil)
      end
    end

    class EventWorkItem < StepWorkItem
      attr_reader :event

      def initialize(execution_plan_id, step, event)
        super(execution_plan_id, step)
        @event = event
      end

      def execute
        @step.execute(@event.event)
      end
    end

    class FinalizeWorkItem < WorkItem
      def initialize(execution_plan_id, sequential_manager)
        super(execution_plan_id)
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
      @plan_ids_in_rescue = Set.new
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
      event.result.fail e.message
      raise e
    end

    def work_finished(work)
      manager = @execution_plan_managers[work.execution_plan_id]
      unless_done(manager, manager.what_is_next(work))
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
        finish_manager(manager)
        return []
      else
        return work_items
      end
    end

    def finish_manager(manager)
      @execution_plan_managers.delete(manager.execution_plan.id)
      if rescue?(manager)
        rescue!(manager)
      else
        set_future(manager)
      end
    end

    def rescue?(manager)
      return false if @world.terminating?
      @world.auto_rescue && manager.execution_plan.state == :paused &&
        !@plan_ids_in_rescue.include?(manager.execution_plan.id)
    end

    def rescue!(manager)
      # TODO: after moving to concurrent-ruby actors, there should be better place
      # to put this logic of making sure we don't run rescues in endless loop
      @plan_ids_in_rescue << manager.execution_plan.id
      rescue_plan_id = manager.execution_plan.rescue_plan_id
      if rescue_plan_id
        @world.executor.execute(rescue_plan_id, manager.future, false)
      else
        set_future(manager)
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
      finished.fail e
      nil
    end

    def set_future(manager)
      @plan_ids_in_rescue.delete(manager.execution_plan.id)
      manager.future.success manager.execution_plan
    end
  end
end
