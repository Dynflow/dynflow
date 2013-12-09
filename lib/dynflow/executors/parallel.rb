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

        ProgressUpdate = type do
          fields! execution_plan_id: String,
                  step_id:           Fixnum,
                  done:              Boolean,
                  args:              Array
        end

        Finalize = type do
          fields! sequential_manager: SequentialManager,
                  execution_plan_id:  String
        end

        Step = type do
          fields! step:              ExecutionPlan::Steps::AbstractFlowStep,
                  execution_plan_id: String
        end

        ProgressUpdateStep = type do
          fields! step:              ExecutionPlan::Steps::AbstractFlowStep,
                  execution_plan_id: String,
                  progress_update:   ProgressUpdate
        end

        Work       = type { variants Step, ProgressUpdateStep, Finalize }
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

      def update_progress(suspended_action, done, *args)
        @core << ProgressUpdate[
            suspended_action.execution_plan_id, suspended_action.step_id, done, args]
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
