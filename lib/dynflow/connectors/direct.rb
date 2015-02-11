module Dynflow
  module Connectors
    class Direct < Abstract

      class Core < Actor

        def initialize
          @worlds = {}
          @round_robin_counter = 0
        end

        def start_listening(world)
          @worlds[world.id] = world
        end

        def stop_listening(world)
          @worlds.delete(world.id)
          terminate! if @worlds.empty?
        end

        def handle_envelope(envelope)
          if world = find_receiver(envelope)
            world.receive(envelope)
          else
            log(Logger::ERROR, "Receiver for envelope #{ envelope } not found")
          end
        end

        private

        def find_receiver(envelope)
          receiver = if Dispatcher::AnyExecutor === envelope.receiver_id
                       executors[inc_round_robin_counter]
                     else
                       @worlds[envelope.receiver_id]
                     end
          raise Dynflow::Error, "No executor available" unless receiver
          return receiver
        end

        def executors
          @worlds.values.find_all(&:executor)
        end

        def inc_round_robin_counter
          @round_robin_counter += 1
          executors_size = executors.size
          if executors_size > 0
            @round_robin_counter %= executors_size
          else
            @round_robin_counter = 0
          end
        end
      end

      def initialize(world = nil)
        @core  = Core.spawn('connector-direct-core')
        start_listening(world) if world
      end

      def start_listening(world)
        @core.ask([:start_listening, world])
      end

      def stop_listening(world)
        @core.ask([:stop_listening, world])
      end

      def send(envelope)
        @core.ask([:handle_envelope, envelope])
      end

      def terminate
        # The core terminates itself when last world stops listening
      end
    end
  end
end
