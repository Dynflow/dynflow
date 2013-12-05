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
        accepted = (@core << Core::Execute[execution_plan_id, future]).value
        raise accepted.value if accepted.value.is_a? Exception
        return future
      end

      def update_progress(suspended_action, done, *args)
        raise 'updates are handled in a process with real executor'
      end

      def terminate!
        @core.terminate!
      end

      def initialized
        @core.initialized
      end
    end
  end
end
