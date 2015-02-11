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

      def initialize(world, pool_size = 10)
        super(world)
        @core = Core.spawn name:        'parallel-executor-core',
                           args:        [world, pool_size],
                           initialized: @core_initialized = Concurrent::IVar.new
      end

      def execute(execution_plan_id, finished = Concurrent::IVar.new)
        @core.ask([:handle_execution, execution_plan_id, finished]).value!
        finished
      rescue Concurrent::Actor::ActorTerminated => error
        dynflow_error = Dynflow::Error.new('executor terminated')
        finished.fail dynflow_error unless finished.completed?
        raise dynflow_error
      rescue => e
        finished.fail e unless finished.completed?
        raise e
      end

      def event(execution_plan_id, step_id, event, future = Concurrent::IVar.new)
        @core.ask([:handle_event, Event[execution_plan_id, step_id, event, future]])
        future
      end

      def terminate(future = Concurrent::IVar.new)
        @core.tell([:start_termination, future])
        future
      end

      def initialized
        @core_initialized
      end
    end
  end
end
