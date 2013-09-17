module Dynflow
  module Executors
    class Parallel < Abstract

      require 'dynflow/executors/parallel/micro_actor'
      require 'dynflow/executors/parallel/sequence_cursor'
      require 'dynflow/executors/parallel/flow_manager'
      require 'dynflow/executors/parallel/execution_plan_manager'
      require 'dynflow/executors/parallel/sequential_manager'
      require 'dynflow/executors/parallel/core'
      require 'dynflow/executors/parallel/pool'
      require 'dynflow/executors/parallel/worker'

      # actor messages
      Terminate = Algebrick.type { fields future: Future }
      Boolean   = Algebrick.type { variants TrueClass, FalseClass }

      Execution = Algebrick.type do
        fields execution_plan_id: String,
               accepted:          Future,
               finished:          Future
      end

      ProgressUpdate = Algebrick.type do
        fields execution_plan_id: String,
               step_id:           Fixnum,
               done:              Boolean,
               args:              Array
      end

      Finalize = Algebrick.type do
        fields sequential_manager: SequentialManager,
               execution_plan_id:  String
      end

      Step = Algebrick.type do
        fields step:              ExecutionPlan::Steps::AbstractFlowStep,
               execution_plan_id: String
      end

      ProgressUpdateStep = Algebrick.type do
        fields step:              ExecutionPlan::Steps::AbstractFlowStep,
               execution_plan_id: String,
               resumption:        ProgressUpdate
      end

      Work       = Algebrick.type { variants Step, ProgressUpdateStep, Finalize }
      PoolDone   = Algebrick.type { fields work: Work }
      WorkerDone = Algebrick.type { fields work: Work, worker: Worker }

      [Execution, ProgressUpdate, Finalize, Step, ProgressUpdateStep, PoolDone, WorkerDone].
          each &:add_all_field_method_accessors

      # TODO this definition is ugly :/ change to DSL after algebrick update

      def initialize(world, pool_size = 10)
        super(world)
        @core = Core.new world, pool_size
      end

      def execute(execution_plan_id)
        @core << Execution[execution_plan_id, future = Future.new]
        return future
      end

      def update_progress(suspended_action, done, *args)
        @core << ProgressUpdate[
            suspended_action.execution_plan_id, suspended_action.step_id, done, args]
      end
    end
  end
end
