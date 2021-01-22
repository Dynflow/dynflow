# frozen_string_literal: true
require 'mqtt'

module Dynflow
  module Connectors
    class MQTT < Abstract

      class MQTTListerner
        def initialize(core, world_id, client_attrs)
          @core     = core
          @world_id = world_id
          @started  = Concurrent::AtomicReference.new
          @client   = nil
          @client_attrs = client_attrs
        end

        def started?
          @started.get
        end

        def start
          @started.set true
          @thread = Thread.new do
            @client = ::MQTT::Client.connect(@client_attrs)
            @client.subscribe("dynflow_envelopes/#{@world_id}")
            @client.get do |topic, message|
              message = Dynflow.serializer.load(MultiJson.load(message))
              if message[:receiver_id] == @world_id
                puts "#{@world_id} RECEIVED #{message}"
                @core.tell([:handle_envelope, message])
              end
            end
          end
        end

        def stop
          @started.set false
          @client.disconnect
          @thread.kill
          @client = @thread = nil
        end
      end

      class Core < Actor
        def initialize(connector, client_attrs)
          @connector = connector
          @world = nil
          @executor_round_robin = RoundRobin.new
          @stopped = false
          @client_attrs = client_attrs
          # TODO:
          @client = ::MQTT::Client.connect(client_attrs)
        end

        def stopped?
          !!@stopped
        end

        def start_listening(world)
          @world = world
          @stopped = false
          mqtt_subscribe
        end

        def stop_receiving_new_work
          @world.coordinator.deactivate_world(@world.registered_world)
        end

        def stop_listening
          @stopped = true
          mqtt_unsubscribe
        end

        def handle_envelope(envelope)
          world_id = find_receiver(envelope)
          if world_id == @world.id
            if @stopped
              log(Logger::ERROR, "Envelope #{envelope} received for stopped world")
            else
              @connector.receive(@world, envelope)
            end
          else
            send_envelope(update_receiver_id(envelope, world_id))
          end
        end

        private

        def mqtt_subscribe
          @mqtt_listener ||= MQTTListerner.new(self, @world.id, @client_attrs)
          @mqtt_listener.start unless @mqtt_listener.started?
        end

        def mqtt_unsubscribe
          @mqtt_listener.stop if @mqtt_listener
        end

        def send_envelope(envelope)
          payload = MultiJson.dump(Dynflow.serializer.dump(envelope))
          @client.publish("dynflow_envelopes/#{envelope.receiver_id}", payload)
        rescue => e
          log(Logger::ERROR, "Sending envelope failed on #{e}")
        end

        def update_receiver_id(envelope, new_receiver_id)
          Dispatcher::Envelope[envelope.request_id, envelope.sender_id, new_receiver_id, envelope.message]
        end

        def find_receiver(envelope)
          if Dispatcher::AnyExecutor === envelope.receiver_id
            any_executor.id
          else
            envelope.receiver_id
          end
        end

        def any_executor
          @executor_round_robin.data = @world.coordinator.find_worlds(true)
          @executor_round_robin.next or raise Dynflow::Error, "No executor available"
        end
      end

      def initialize(client_attrs, world = nil)
        @core = Core.spawn('connector-database-core', self, client_attrs)
        start_listening(world) if world
      end

      def start_listening(world)
        @core.ask([:start_listening, world])
      end

      def stop_receiving_new_work(_, timeout = nil)
        @core.ask(:stop_receiving_new_work).wait(timeout)
      end

      def stop_listening(_, timeout = nil)
        @core.ask(:stop_listening).then { @core.ask(:terminate!) }.wait(timeout)
      end

      def send(envelope)
        Telemetry.with_instance { |t| t.increment_counter(:dynflow_connector_envelopes, 1, :world => envelope.sender_id, :direction => 'outgoing') }
        @core.ask([:handle_envelope, envelope])
      end

      def prune_undeliverable_envelopes(world)
        # Just a noop
        0
      end
    end
  end
end
