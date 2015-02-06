module Dynflow
  module Executors
    class Parallel < Abstract
      class ExecutionPlanManager
        include Algebrick::TypeCheck
        include Algebrick::Matching

        attr_reader :execution_plan, :future

        def initialize(world, execution_plan, future)
          @world                 = Type! world, World
          @execution_plan        = Type! execution_plan, ExecutionPlan
          @future                = Type! future, Concurrent::IVar
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
          Work::Step[step, execution_plan.id].tap do |work|
            @running_steps_manager.add(step, work)
          end
        end

        def try_to_terminate
          @running_steps_manager.try_to_terminate
        end

        # @return [Array<Work>] of Work items to continue with
        def what_is_next(work)
          Type! work, Work

          compute_next_from_step =-> step do
            raise unless @run_manager
            raise if @run_manager.done?

            next_steps = @run_manager.what_is_next(step)
            if @run_manager.done?
              start_finalize or finish
            else
              next_steps.map { |s| prepare_next_step(s) }
            end
          end

          match(work,
                (on Work::Step.(step: ~any) | Work::Event.(step: ~any) do |step|
                   execution_plan.steps[step.id] = step
                   suspended, work = @running_steps_manager.done(step)
                   unless suspended
                     work = compute_next_from_step.call step
                   end
                   work
                 end),
                (on Work::Finalize do
                   raise unless @finalize_manager
                   finish
                 end))
        end

        def event(event)
          Type! event, Parallel::Event
          raise unless event.execution_plan_id == @execution_plan.id
          @running_steps_manager.event(event)
        end

        def done?
          (!@run_manager || @run_manager.done?) && (!@finalize_manager || @finalize_manager.done?)
        end

        private

        def no_work
          raise "No work but not done" unless done?
          []
        end

        def start_run
          unless execution_plan.run_flow.empty?
            raise 'run phase already started' if @run_manager
            @run_manager = FlowManager.new(execution_plan, execution_plan.run_flow)
            @run_manager.start.map { |s| prepare_next_step(s) }.tap { |a| raise if a.empty? }
          end
        end

        def start_finalize
          unless execution_plan.finalize_flow.empty?
            raise 'finalize phase already started' if @finalize_manager
            @finalize_manager = SequentialManager.new(@world, execution_plan)
            Work::Finalize[@finalize_manager, execution_plan.id]
          end
        end

        def finish
          execution_plan.execution_history.add('finish execution', @world.id)
          @execution_plan.update_state(execution_plan.error? ? :paused : :stopped)
          return no_work
        end

      end
    end
  end
end
