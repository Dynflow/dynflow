module Dynflow
  module Executors
    class Parallel < Abstract

      require 'dynflow/executors/parallel/micro_actor'
      require 'dynflow/executors/parallel/sequence_cursor'
      require 'dynflow/executors/parallel/flow_manager'
      require 'dynflow/executors/parallel/execution_plan_manager'
      require 'dynflow/executors/parallel/core'
      require 'dynflow/executors/parallel/pool'
      require 'dynflow/executors/parallel/worker'

      # actor messages
      Execution   = Algebrick::Product.new execution_plan_id: String, future: Future
      Resumption  = Algebrick::Product.new execution_plan_id: String, step_id: Fixnum,
                                           method:            Symbol, args: Array
      Finalize    = Algebrick::Product.new sequential_manager: SequentialManager,
                                           execution_plan_id:  String
      Step        = Algebrick::Product.new step:              ExecutionPlan::Steps::AbstractFlowStep,
                                           execution_plan_id: String
      ResumedStep = Algebrick::Product.new step:              ExecutionPlan::Steps::AbstractFlowStep,
                                           execution_plan_id: String, resumption: Resumption
      Work        = Algebrick::Variant.new Step, ResumedStep, Finalize
      PoolDone    = Algebrick::Product.new work: Work
      WorkerDone  = Algebrick::Product.new work: Work, worker: Worker

      [Step, ResumedStep, Finalize].
          each { |t| t.add_field_method_accessor :execution_plan_id }

      # TODO this definition is ugly :/ change to DSL after algebrick update

      def initialize(world, pool_size = 10)
        super(world)
        @core = Core.new world, pool_size
      end

      def execute(execution_plan_id)
        @core << Execution[execution_plan_id, future = Future.new]
        return future
      end

      # TODO replace with update_progress
      def resume(execution_plan_id, step_id, method, *args)
        @core << Resumption[execution_plan_id, step_id, method, args]
      end
    end
  end
end
