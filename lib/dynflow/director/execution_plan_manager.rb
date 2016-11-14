module Dynflow
  class Director
    class ExecutionPlanManager
      include Algebrick::TypeCheck
      include Algebrick::Matching

      attr_reader :execution_plan, :future

      def initialize(world, execution_plan, future)
        @world                 = Type! world, World
        @execution_plan        = Type! execution_plan, ExecutionPlan
        @future                = Type! future, Concurrent::Edge::Future
        @running_steps_manager = RunningStepsManager.new(world)

        unless [:planned, :paused].include? execution_plan.state
          raise "execution_plan is not in pending or paused state, it's #{execution_plan.state}"
        end
        execution_plan.execution_history.add('start execution', @world.id)
        execution_plan.update_state(:running)
      end

      def start
        raise "The future was already set" if @future.completed?
        start_run or start_finalize or finish
      end

      def prepare_next_step(step)
        StepWorkItem.new(execution_plan.id, step).tap do |work|
          @running_steps_manager.add(step, work)
        end
      end

      # @return [Array<WorkItem>] of Work items to continue with
      def what_is_next(work)
        Type! work, WorkItem

        case work
        when StepWorkItem
          step = work.step
          execution_plan.steps[step.id] = step
          suspended, work = @running_steps_manager.done(step)
          work = compute_next_from_step(step) unless suspended
          work
        when FinalizeWorkItem
          raise "Finalize work item without @finalize_manager ready" unless @finalize_manager
          finish
        end
      end

      def event(event)
        Type! event, Event
        unless event.execution_plan_id == @execution_plan.id
          raise "event #{event.inspect} doesn't belong to plan #{@execution_plan.id}"
        end
        @running_steps_manager.event(event)
      end

      def done?
        (!@run_manager || @run_manager.done?) && (!@finalize_manager || @finalize_manager.done?)
      end

      def terminate
        @running_steps_manager.terminate
      end

      private

      def compute_next_from_step(step)
        raise "run manager not set" unless @run_manager
        raise "run manager already done" if @run_manager.done?

        next_steps = @run_manager.what_is_next(step)
        if @run_manager.done?
          start_finalize or finish
        else
          next_steps.map { |s| prepare_next_step(s) }
        end
      end

      def no_work
        raise "No work but not done" unless done?
        []
      end

      def start_run
        return if execution_plan.run_flow.empty?
        raise 'run phase already started' if @run_manager
        @run_manager = FlowManager.new(execution_plan, execution_plan.run_flow)
        @run_manager.start.map { |s| prepare_next_step(s) }.tap { |a| raise if a.empty? }
      end

      def start_finalize
        return if execution_plan.finalize_flow.empty?
        raise 'finalize phase already started' if @finalize_manager
        @finalize_manager = SequentialManager.new(@world, execution_plan)
        [FinalizeWorkItem.new(execution_plan.id, @finalize_manager)]
      end

      def finish
        execution_plan.execution_history.add('finish execution', @world.id)
        @execution_plan.update_state(execution_plan.error? ? :paused : :stopped)
        return no_work
      end

    end
  end
end
