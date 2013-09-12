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
      Boolean            = Algebrick::Variant.new TrueClass, FalseClass
      Execution          = Algebrick::Product.new execution_plan_id: String,
                                                  future:            Future
      ProgressUpdate     = Algebrick::Product.new execution_plan_id: String,
                                                  step_id:           Fixnum,
                                                  done:              Boolean,
                                                  args:              Array
      Finalize           = Algebrick::Product.new sequential_manager: SequentialManager,
                                                  execution_plan_id:  String
      Step               = Algebrick::Product.new step:              ExecutionPlan::Steps::AbstractFlowStep,
                                                  execution_plan_id: String
      ProgressUpdateStep = Algebrick::Product.new step:              ExecutionPlan::Steps::AbstractFlowStep,
                                                  execution_plan_id: String,
                                                  resumption:        ProgressUpdate
      Work               = Algebrick::Variant.new Step, ProgressUpdateStep, Finalize
      PoolDone           = Algebrick::Product.new work: Work
      WorkerDone         = Algebrick::Product.new work:   Work,
                                                  worker: Worker

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
