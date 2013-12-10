module Dynflow
  module Executors
    class Parallel < Abstract

      require 'dynflow/executors/parallel/sequence_cursor'
      require 'dynflow/executors/parallel/flow_manager'
      require 'dynflow/executors/parallel/work_queue'
      require 'dynflow/executors/parallel/execution_plan_manager'
      require 'dynflow/executors/parallel/sequential_manager'
      require 'dynflow/executors/parallel/core'
      require 'dynflow/executors/parallel/pool'
      require 'dynflow/executors/parallel/worker'

      # actor messages
      Algebrick.types do
        Boolean = type { variants TrueClass, FalseClass }

        Execution = type do
          fields! execution_plan_id: String,
                  accepted:          Future,
                  finished:          Future
        end

        Event = type do
          fields! execution_plan_id: String,
                  step_id:           Fixnum,
                  event:             Object
        end

        Work = type do |work|
          work::Finalize = type do
            fields! sequential_manager: SequentialManager,
                    execution_plan_id:  String
          end

          work::Step = type do
            fields! step:              ExecutionPlan::Steps::AbstractFlowStep,
                    execution_plan_id: String
          end

          work::Event = type do
            fields! step:              ExecutionPlan::Steps::AbstractFlowStep,
                    execution_plan_id: String,
                    event:             Event
          end

          variants work::Step, work::Event, work::Finalize
        end

        PoolDone   = type do
          fields! work: Work
        end
        WorkerDone = type do
          fields! work: Work, worker: Worker
        end
      end

      def initialize(world, pool_size = 10)
        super(world)
        @core = Core.new world, pool_size
      end

      def execute(execution_plan_id, finished = Future.new)
        @core << Execution[execution_plan_id, accepted = Future.new, finished]
        raise accepted.value if accepted.value.is_a? Exception
        finished
      end

      def event(suspended_action, event)
        @core << Event[suspended_action.execution_plan_id, suspended_action.step_id, event]
      end

      def terminate(future = Future.new)
        @core.ask(MicroActor::Terminate, future)
      end

      def initialized
        @core.initialized
      end
    end
  end
end
