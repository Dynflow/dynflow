module Dynflow
  module Executors
    class Parallel < Abstract
      require 'dynflow/executors/parallel/core'
      require 'dynflow/executors/parallel/pool'
      require 'dynflow/executors/parallel/worker'

      def initialize(world, heartbeat_interval, queues_options = { :default => { :pool_size => 5 }})
        super(world)
        @core = Core.spawn name:        'parallel-executor-core',
                           args:        [world, heartbeat_interval, queues_options],
                           initialized: @core_initialized = Concurrent::Promises.resolvable_future
      end

      def execute(execution_plan_id, finished = Concurrent::Promises.resolvable_future, wait_for_acceptance = true)
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

      def event(execution_plan_id, step_id, event, future = Concurrent::Promises.resolvable_future)
        @core.ask([:handle_event, Director::Event[execution_plan_id, step_id, event, future]])
        future
      end

      def terminate(future = Concurrent::Promises.resolvable_future)
        @core.tell([:start_termination, future])
        future
      end

      def execution_status(execution_plan_id = nil)
        @core.ask!([:execution_status, execution_plan_id])
      end

      def initialized
        @core_initialized
      end
    end
  end
end
