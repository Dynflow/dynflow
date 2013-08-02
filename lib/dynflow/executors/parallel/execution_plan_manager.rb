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
          @finalize_manager = SequentialManager.new(world, execution_plan.id) unless execution_plan.finalize_flow.empty?
          #finalize_manager = FlowManager.new(execution_plan, execution_plan.finalize_flow) unless execution_plan.finalize_flow.empty?
          #@flow_managers = [run_manager, finalize_manager].compact
          #@iteration     = 0
          raise unless @run_manager || @finalize_manager

          execution_plan.state = :running
          execution_plan.save
        end

        def start
          if @run_manager
            @run_manager.start.map { |s| Step[s, execution_plan.id] }
          else
            [Finalize[@finalize_manager, execution_plan.id]]
          end
        end

        # @return [Array<Work>] of Work items to continue with
        def what_is_next(work)
          is_kind_of! work, Work

          match work,
                Step.(~any, any) --> step do
                  raise unless @run_manager && !@run_manager.done?
                  next_steps = @run_manager.what_is_next(step)

                  if @run_manager.done?
                    if @finalize_manager
                      [Finalize[@finalize_manager, execution_plan.id]]
                    else
                      return no_work
                    end
                  else
                    next_steps.map { |s| Step[s, execution_plan.id] }
                  end
                end,
                Finalize.(any, any) --> do
                  raise unless @finalize_manager
                  @execution_plan.state = execution_plan.result == :error ? :paused : :stopped
                  @execution_plan.save
                  @future.set @execution_plan
                  return no_work
                end

          ## TODO
          #next_steps = current_manager.what_is_next(flow_step)
          #
          #if current_manager.done?
          #  raise 'invalid state' unless next_steps.empty?
          #  if next_manager?
          #    next_manager!
          #    return start
          #  else
          #    @execution_plan.state = execution_plan.result == :error ? :paused : :stopped
          #    @execution_plan.save
          #    @future.set @execution_plan
          #  end
          #end
          #
          #return next_steps
        end

        def done?
          (!@run_manager || @run_manager.done?) && (!@finalize_manager || @finalize_manager.done?)
        end

        private

        def no_work
          raise unless done?
          []
        end

        #def run_phase?
        #  phase == :run
        #end
        #
        #def finalize_phase?
        #  phase == :finalize
        #end
        #
        #def phase
        #  if @run_manager
        #    if !@run_manager.done?
        #      :run
        #    elsif @finalize_manager
        #      :finalize
        #    else
        #      raise
        #    end
        #  else
        #    @finalize_manager ? :finalize : raise
        #  end
        #end

        #def current_manager
        #  @flow_managers[@iteration]
        #end
        #
        #def next_manager?
        #  @iteration < @flow_managers.size-1
        #end
        #
        #def next_manager!
        #  @iteration += 1
        #end

      end
    end
  end
end
