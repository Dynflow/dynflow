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

          execution_plan.set_state(:running)
        rescue => error
          # TODO use logger
          # $stderr.puts "FATAL #{error.message} (#{error.class})\n#{error.backtrace.join("\n")}"
          @future.set(error)
        end

        def start
          raise "The future was already set" if @future.ready?
          start_run or start_finalize or finish
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
                    start_finalize or finish
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
          raise "No work but not done" unless done?
          []
        end

        def start_run
          unless execution_plan.run_flow.empty?
            raise 'run phase already started' if @run_manager
            @run_manager = FlowManager.new(execution_plan, execution_plan.run_flow)
            @run_manager.start.map { |s| Step[s, execution_plan.id] }
          end
        end

        def start_finalize
          unless execution_plan.finalize_flow.empty?
            raise 'finalize phase already started' if @finalize_manager
            @finalize_manager = SequentialManager.new(@world, execution_plan.id)
            [Finalize[@finalize_manager, execution_plan.id]]
          end
        end

        def finish
          @execution_plan.set_state(execution_plan.error? ? :paused : :stopped)
          @future.set @execution_plan
          return no_work
        end

      end
    end
  end
end
