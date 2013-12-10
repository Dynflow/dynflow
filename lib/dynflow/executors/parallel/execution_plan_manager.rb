module Dynflow
  module Executors
    class Parallel < Abstract
      class ExecutionPlanManager
        include Algebrick::TypeCheck
        include Algebrick::Matching

        attr_reader :execution_plan, :future

        def initialize(world, execution_plan, future)
          @world          = Type! world, World
          @execution_plan = Type! execution_plan, ExecutionPlan
          @future         = Type! future, Future
          @events         = WorkQueue.new

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
                  execution_plan.update_execution_time step.execution_time if step.state != :suspended
                  compute_next_from_step.call step
                end,
                Work::Event.(:step) >-> step do
                  @events.shift(step.id)

                  if step.state == :suspended
                    @events.first(step.id)
                  else
                    # TODO it can be probably ignored
                    #while (event = @events.shift(step.id))
                    #  @world.logger.warn "step #{step.execution_plan_id}:#{step.id} dropping event #{event.event}"
                    #end
                    raise 'assert' unless @events.empty?(step.id)

                    execution_plan.update_execution_time step.execution_time
                    compute_next_from_step.call step
                  end
                end,
                Work::Finalize.(any, any) >-> do
                  raise unless @finalize_manager
                  finish
                end
        end

        # @return [ProgressUpdateStep]
        def event(event)
          Type! event, Event

          step          = @execution_plan.steps[event.step_id]
          can_run_event = @events.empty?(step.id)
          work          = Work::Event[step, @execution_plan.id, event]
          @events.push(step.id, work)
          work if can_run_event
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
