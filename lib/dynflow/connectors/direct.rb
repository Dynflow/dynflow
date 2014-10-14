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

      class Core < MicroActor

        def initialize(*args)
          super
          @worlds = {}
          @round_robin_counter = 0
        end

        def termination
          try_to_terminate
        end

        private

        def on_message(msg)
          match msg,
                (on StartListening.(~Dynflow::World.to_m) do |world|
                   @worlds[world.id] = world
                 end),
                (on StopListening.(~Dynflow::World.to_m) do |world|
                   @worlds.delete(world.id)
                   try_to_terminate if terminating?
                 end),
                (on Terminate do
                   terminate!
                 end),
                (on ~Dispatcher::Envelope do |envelope|
                   if world = find_receiver(envelope)
                     world.receive(envelope)
                   else
                     logger.error("Receiver for envelope #{ envelope } not found")
                   end
                 end)
        end

        def try_to_terminate
          self << Terminate if @worlds.empty?
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
          @round_robin_counter %= executors.size
        end
      end

      def initialize(logger, world = nil)
        @core  = Core.new(logger)
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
      end

      def terminate
        @core << MicroActor::Terminate
      end
    end
  end
end
