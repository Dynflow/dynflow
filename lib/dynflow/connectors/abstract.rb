# frozen_string_literal: true

module Dynflow
  module Connectors
    class Abstract
      include Algebrick::TypeCheck
      include Algebrick::Matching

      def start_listening(world)
        raise NotImplementedError
      end

      def stop_receiving_new_work(_, timeout = nil)
        raise NotImplementedError
      end

      def stop_listening(world, timeout = nil)
        raise NotImplementedError
      end

      def terminate
        raise NotImplementedError
      end

      def send(envelope)
        raise NotImplementedError
      end

      def prune_undeliverable_envelopes(world)
        raise NotImplementedError
      end

      # we need to pass the world, as the connector can be shared
      # between words: we need to know the one to send the message to
      def receive(world, envelope)
        Type! envelope, Dispatcher::Envelope
        Telemetry.with_instance { |t| t.increment_counter(:dynflow_connector_envelopes, 1, :world => world.id, :direction => 'incoming') }
        match(envelope.message,
          (on Dispatcher::Ping do
             response_envelope = envelope.build_response_envelope(Dispatcher::Pong, world)
             send(response_envelope)
           end),
          (on Dispatcher::Request do
             world.executor_dispatcher.tell([:handle_request, envelope])
           end),
          (on Dispatcher::Response do
             world.client_dispatcher.tell([:dispatch_response, envelope])
           end))
      end
    end
  end
end
