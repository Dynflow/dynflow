module Dynflow
  module Executors
    class Parallel < Abstract
      class ExecutionPlanManager
        include Algebrick::TypeCheck
        include Algebrick::Matching

        attr_reader :execution_plan

        def initialize(world, execution_plan, future)
          @world          = is_kind_of! world, World
          @execution_plan = is_kind_of! execution_plan, ExecutionPlan
          @future         = is_kind_of! future, Future

          @run_manager = FlowManager.new(execution_plan, execution_plan.run_flow) unless execution_plan.run_flow.empty?
          raise unless @run_manager || @finalize_manager

          execution_plan.state = :running
          execution_plan.save
        end

        def start
          if @run_manager
            @run_manager.start.map { |s| Step[s, execution_plan.id] }
          else
            start_finalize
          end
        end

        # @return [Array<Work>] of Work items to continue with
        def what_is_next(work)
          is_kind_of! work, Work

          match(work,
                Step.(~any, any) --> step do
                  raise unless @run_manager
                  raise if @run_manager.done?

                  next_steps = @run_manager.what_is_next(step)

                  if @run_manager.done?
                    if !execution_plan.finalize_flow.empty?
                      start_finalize
                    else
                      finish
                    end
                  else
                    next_steps.map { |s| Step[s, execution_plan.id] }
                  end
                end,
                Finalize.(any, any) --> do
                  raise unless @finalize_manager
                  @execution_plan = @finalize_manager.execution_plan
                  finish
                end)
        end

        def done?
          (!@run_manager || @run_manager.done?) && (!@finalize_manager || @finalize_manager.done?)
        end

        private

        def no_work
          raise unless done?
          []
        end

        def start_finalize
          raise 'finalization already started' if @finalize_manager
          @finalize_manager = SequentialManager.new(@world, execution_plan.id)
          [Finalize[@finalize_manager, execution_plan.id]]
        end

        def finish
          @execution_plan.state = execution_plan.result == :error ? :paused : :stopped
          @execution_plan.save
          @future.set @execution_plan
          return no_work
        end

      end
    end
  end
end
