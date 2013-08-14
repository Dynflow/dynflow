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
      Execute    = Algebrick::Product.new execution_plan_id: String, future: Future
      Finalize   = Algebrick::Product.new sequential_amanger: SequentialManager, execution_plan_id: String
      Step       = Algebrick::Product.new step: ExecutionPlan::Steps::AbstractFlowStep, execution_plan_id: String
      Work       = Algebrick::Variant.new Step, Finalize do
        def execution_plan_id
          self[:execution_plan_id]
        end
      end
      PoolDone   = Algebrick::Product.new work: Work
      WorkerDone = Algebrick::Product.new work: Work, worker: Worker

      def initialize(world, pool_size = 10)
        super(world)
        @core = Core.new world, pool_size
      end

      def execute(execution_plan_id)
        @core << Execute[execution_plan_id, future = Future.new]
        return future
      end
    end
  end
end
