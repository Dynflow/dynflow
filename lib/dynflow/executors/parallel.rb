module Dynflow
  module Executors
    class Parallel < Abstract

      require 'dynflow/executors/parallel/micro_actor'
      require 'dynflow/executors/parallel/cursor'
      require 'dynflow/executors/parallel/flow_manager'
      require 'dynflow/executors/parallel/execution_plan_manager'
      require 'dynflow/executors/parallel/core'
      require 'dynflow/executors/parallel/pool'
      require 'dynflow/executors/parallel/worker'

      # actor messages
      Execute    = Algebrick::Product.new execution_plan_id: String, future: Future
      Work       = Algebrick::Product.new step: ExecutionPlan::Steps::AbstractFlowStep
      PoolDone   = Algebrick::Product.new step: ExecutionPlan::Steps::AbstractFlowStep
      WorkerDone = Algebrick::Product.new step: ExecutionPlan::Steps::AbstractFlowStep, worker: Worker

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
