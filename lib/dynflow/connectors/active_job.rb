module Dynflow
  module Connectors
    # TODO: ActiveJob is abstraction already: we might not need any other connectors
    # so we would replace the abstraction to simple object
    class ActiveJob < Abstract
      def initialize(world = nil)
      end

      def start_listening(world)
        # will be handled by specific job provider: we will remove the the listening on client side:
        # in case we need to wait for something, we will just poll for the status
      end

      def stop_receiving_new_work(world, timeout = nil)
        # TODO: make something so that the orchestrator will be rejecting new work while still
        # receiving messages from the workers to finalize the current running tasks
      end

      def stop_listening(world, timeout = nil)
        # TODO: stop the queue processing of the ActiveJob provider
      end

      def send(envelope)
        case envelope.message
        when Dispatcher::Ping
        # TODO: fully replace ping/pong with heartbeat
        when Dispatcher::Response
        # TODO: replace response handling: just assume the work was queued and will be processed
        # failure in delivering the message should be handled by ActiveJob
        when Dispatcher::Request
          serialized_envelope = Dynflow.serializer.dump(envelope)
          Executors::ActiveJob::ProcessRequest.perform_later(serialized_envelope)
        end
      end
    end
  end
end
