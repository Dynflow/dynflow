module Dynflow
  module Executors
    class Parallel < Abstract
      class ExecutionPlanManager
        include Algebrick::TypeCheck
        include Algebrick::Matching

        attr_reader :execution_plan, :future

        def initialize(world, execution_plan, future)
          @world                     = Type! world, World
          @execution_plan            = Type! execution_plan, ExecutionPlan
          @future                    = Type! future, Future
          @events                    = WorkQueue.new
          @suspended_actions_manager = SuspendedStepsManager.new(world)

          unless [:planned, :paused].include? execution_plan.state
            raise "execution_plan is not in pending or paused state, it's #{execution_plan.state}"
          end
          execution_plan.update_state(:running)
        end

        def start
          raise "The future was already set" if @future.ready?
          start_run or start_finalize or finish
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
              next_steps.map { |s| Work::Step[s, execution_plan.id] }
            end
          end

          match work,

                Work::Step.(:step) >-> step do
                  if step.state == :suspended
                    @suspended_actions_manager.add step
                  else
                    execution_plan.update_execution_time step.execution_time
                  end
                  compute_next_from_step.call step
                end,

                Work::Event.(:step) >-> step do
                  suspended, work = @suspended_actions_manager.done(step)

                  if suspended
                    work
                  else
                    execution_plan.update_execution_time step.execution_time
                    compute_next_from_step.call step
                  end
                end,

                Work::Finalize.(any, any) >-> do
                  raise unless @finalize_manager
                  finish
                end
        end

        def event(event)
          Type! event, Event
          raise unless event.execution_plan_id == @execution_plan.id
          @suspended_actions_manager.event(event)
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
            @run_manager.start.map { |s| Work::Step[s, execution_plan.id] }.tap { |a| raise if a.empty? }
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
          @execution_plan.update_state(execution_plan.error? ? :paused : :stopped)
          return no_work
        end

      end
    end
  end
end
