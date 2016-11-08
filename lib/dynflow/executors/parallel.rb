module Dynflow
  module Executors
    class Parallel < Abstract
      require 'dynflow/executors/parallel/core'
      require 'dynflow/executors/parallel/pool'
      require 'dynflow/executors/parallel/worker'

      def initialize(world, pool_size = 10)
        super(world)
        @core = Core.spawn name:        'parallel-executor-core',
                           args:        [world, pool_size],
                           initialized: @core_initialized = Concurrent.future
      end

      def execute(execution_plan_id, finished = Concurrent.future, wait_for_acceptance = true)
        accepted = @core.ask([:handle_execution, execution_plan_id, finished])
        accepted.value! if wait_for_acceptance
        finished
      rescue Concurrent::Actor::ActorTerminated => error
        dynflow_error = Dynflow::Error.new('executor terminated')
        finished.fail dynflow_error unless finished.completed?
        raise dynflow_error
      rescue => e
        finished.fail e unless finished.completed?
        raise e
      end

      def event(execution_plan_id, step_id, event, future = Concurrent.future)
        @core.ask([:handle_event, Director::Event[execution_plan_id, step_id, event, future]])
        future
      end

      def terminate(future = Concurrent.future)
        @core.tell([:start_termination, future])
        future
      end

      def initialized
        @core_initialized
      end
    end
  end
end
