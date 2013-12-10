require 'multi_json'
require 'socket'

module Dynflow
  module Executors
    class RemoteViaSocket < Abstract
      require 'dynflow/executors/remote_via_socket/manager'
      require 'dynflow/executors/remote_via_socket/core'

      include Listeners::Serialization
      include Algebrick::Matching

      def initialize(world, socket_path)
        super world
        @core = Core.new world, socket_path
      end

      def execute(execution_plan_id, future = Future.new)
        accepted = @core.ask(Core::Execute[execution_plan_id, future]).value
        raise accepted.value if accepted.value.is_a? Exception
        return future
      end

      def event(suspended_action, event)
        raise 'events are handled in a process with real executor'
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
