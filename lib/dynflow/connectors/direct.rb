# frozen_string_literal: true

module Dynflow
  module Connectors
    class Direct < Abstract
      class Core < Actor
        def initialize(connector)
          @connector = connector
          @worlds = {}
          @executor_round_robin = RoundRobin.new
        end

        def start_listening(world)
          @worlds[world.id] = world
          @executor_round_robin.add(world) if world.executor
        end

        def stop_receiving_new_work(world)
          @executor_round_robin.delete(world)
        end

        def stop_listening(world)
          @worlds.delete(world.id)
          @executor_round_robin.delete(world) if world.executor
          reference.tell(:terminate!) if @worlds.empty?
        end

        def handle_envelope(envelope)
          if world = find_receiver(envelope)
            @connector.receive(world, envelope)
          else
            log(Logger::ERROR, "Receiver for envelope #{envelope} not found")
          end
        end

        private

        def find_receiver(envelope)
          receiver = if Dispatcher::AnyExecutor === envelope.receiver_id
                       @executor_round_robin.next
                     else
                       @worlds[envelope.receiver_id]
                     end
          raise Dynflow::Error, "No executor available" unless receiver
          return receiver
        end
      end

      def initialize(world = nil)
        @core = Core.spawn('connector-direct-core', self)
        start_listening(world) if world
      end

      def start_listening(world)
        @core.ask([:start_listening, world])
      end

      def stop_receiving_new_work(world, timeout = nil)
        @core.ask([:stop_receiving_new_work, world]).wait(timeout)
      end

      def stop_listening(world, timeout = nil)
        @core.ask([:stop_listening, world]).wait(timeout)
      end

      def send(envelope)
        Telemetry.with_instance { |t| t.increment_counter(:dynflow_connector_envelopes, 1, :world => envelope.sender_id) }
        @core.ask([:handle_envelope, envelope])
      end

      def prune_undeliverable_envelopes(_world)
        # This is a noop
        0
      end
    end
  end
end
