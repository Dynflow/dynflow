module Dynflow
  module Executors
    module ActiveJob
      class PerformWork < ::ActiveJob::Base
        queue_as :dynflow_worker

        def perform(message)
          puts "hello"
        end
      end

      # handles execution request: this might be either new execution plan
      # or some event to handle on orchestrator side
      class ProcessRequest < ::ActiveJob::Base
        queue_as :dynflow_orchestrator

        # @param request_envelope [Dispatcher::Request] - request to handle on orchestrator side
        #   usually to start new execution or to pass some event
        def perform(serialized_request_envelope)
          request_envelope = Dynflow.serializer.load(serialized_request_envelope)
          Dynflow.orchestrator.executor_dispatcher.tell([:handle_request, request_envelope])
        end
      end

    end
  end
end
