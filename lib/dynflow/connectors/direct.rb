module Dynflow
  module Connectors
    class Direct < Abstract

      StartListening = Algebrick.type do
        fields! world: Dynflow::World
      end

      StopListening = Algebrick.type do
        fields! world: Dynflow::World
      end

      Terminate = Algebrick.atom

      class Core < Concurrent::Actor::Context
        include Algebrick::Matching

        def initialize
          @worlds = {}
          @round_robin_counter = 0
        end

        private

        def on_message(msg)
          match msg,
                (on StartListening.(~Dynflow::World.to_m) do |world|
                   @worlds[world.id] = world
                 end),
                (on StopListening.(~Dynflow::World.to_m) do |world|
                   @worlds.delete(world.id)
                   try_to_terminate
                 end),
                (on Terminate do
                   terminate!
                 end),
                (on ~Dispatcher::Envelope do |envelope|
                   if world = find_receiver(envelope)
                     world.receive(envelope)
                   else
                     log(Logger::ERROR, "Receiver for envelope #{ envelope } not found")
                   end
                 end)
        end

        def try_to_terminate
          terminate! if @worlds.empty?
        end

        def find_receiver(envelope)
          if Dispatcher::AnyExecutor === envelope.receiver_id
            executors[inc_round_robin_counter]
          else
            @worlds[envelope.receiver_id]
          end
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
        @core.ask(StartListening[world])
      end

      def stop_listening(world)
        @core.ask(StopListening[world])
      end

      def send(envelope)
        @core.ask(envelope).value!
      rescue Concurrent::Actor::ActorTerminated => _
        # just drop the message
      end

      def terminate
        # The core terminates itself when last world stops listening
      end
    end
  end
end
