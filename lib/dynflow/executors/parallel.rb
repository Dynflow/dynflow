module Dynflow
  module Executors
    class Parallel < Abstract

      require 'dynflow/executors/parallel/sequence_cursor'
      require 'dynflow/executors/parallel/flow_manager'
      require 'dynflow/executors/parallel/work_queue'
      require 'dynflow/executors/parallel/execution_plan_manager'
      require 'dynflow/executors/parallel/sequential_manager'
      require 'dynflow/executors/parallel/running_steps_manager'
      require 'dynflow/executors/parallel/core'
      require 'dynflow/executors/parallel/pool'
      require 'dynflow/executors/parallel/worker'

      UnprocessableEvent = Class.new(Dynflow::Error)

      Algebrick.type do |work|
        Work = work

        Work::Finalize = type do
          fields! sequential_manager: SequentialManager,
                  execution_plan_id:  String
        end

        Work::Step = type do
          fields! step:              ExecutionPlan::Steps::AbstractFlowStep,
                  execution_plan_id: String
        end

        Work::Event = type do
          fields! step:              ExecutionPlan::Steps::AbstractFlowStep,
                  execution_plan_id: String,
                  event:             Event
        end

        variants Work::Step, Work::Event, Work::Finalize
      end

      PoolDone   = Algebrick.type { fields! work: Work }
      WorkerDone = Algebrick.type { fields! work: Work, worker: Worker }

      def initialize(world, pool_size = 10)
        super(world)
        @core = Core.new world, pool_size
      end

      def execute(execution_plan_id, finished = Future.new)
        @core.ask(Execution[execution_plan_id, finished]).value!
        finished
      rescue => e
        finished.fail e unless finished.ready?
        raise e
      end

      def event(execution_plan_id, step_id, event, future = Future.new)
        @core << Event[execution_plan_id, step_id, event, future]
        future
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
