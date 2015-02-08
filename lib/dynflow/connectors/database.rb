module Dynflow
  module Connectors
    class Database < Abstract

      StartListening = Algebrick.type do
        fields! world: Dynflow::World
      end

      StopListening = Algebrick.type do
        fields! world: Dynflow::World
      end

      CheckInbox         = Algebrick.atom
      PeriodicCheckInbox = Algebrick.atom

      class PostgresListerner
        def initialize(core, world_id, db)
          @core     = core
          @db       = db
          @world_id = world_id
          @started  = false
        end

        def enabled?
          @db.class.name == "Sequel::Postgres::Database"
        end

        def started?
          !!@started
        end

        def start
          @thread = Thread.new do
            @db.listen("world:#{ @world_id }", :loop => true) do
              if @started
                @core << CheckInbox
              else
                break # the listener is stopped: don't continue listening
              end
            end
          end
          @started = true
        end

        def notify(world_id)
          @db.notify("world:#{world_id}")
        end

        def stop
          @started = false
          notify(@world_id)
        end
      end

      class Core < Concurrent::Actor::Context
        include Algebrick::Matching

        attr_reader :polling_interval

        def initialize(polling_interval)
          @world = nil
          @round_robin_counter = 0
          @stopped = false
          @polling_interval = polling_interval
        end

        def stopped?
          !!@stopped
        end

        def behaviour_definition
          [*Concurrent::Actor::Behaviour.base,
           *Concurrent::Actor::Behaviour.user_messages(:just_log)]
        end

        private

        def on_message(msg)
          match msg,
                (on StartListening.(~Dynflow::World.to_m) do |world|
                   @world = world
                   @stopped = false
                   @postgres_listener ||= PostgresListerner.new(self, @world.id, @world.persistence.adapter.db)
                   postgres_listen_start
                   self << PeriodicCheckInbox
                 end),
                (on StopListening.(~Dynflow::World.to_m) do |world|
                   @stopped = true
                   postgres_listen_stop
                 end),
                (on PeriodicCheckInbox do
                   self << CheckInbox
                   @world.clock.ping(self, polling_interval, PeriodicCheckInbox) unless @stopped
                 end),
                (on CheckInbox do
                   return unless @world
                   receive_envelopes
                 end),
                (on ~Dispatcher::Envelope do |envelope|
                   world_id = find_receiver(envelope)
                   if world_id == @world.id
                     if @stopped
                       log(Logger::ERROR, "Envelope #{envelope} received for stopped world")
                     else
                       @world.receive(envelope)
                     end
                   else
                     send_envelope(update_receiver_id(envelope, world_id))
                   end
                 end)
        end

        def postgres_listen_start
          @postgres_listener.start if @postgres_listener.enabled? && !@postgres_listener.started?
        end

        def postgres_listen_stop
          @postgres_listener.stop if @postgres_listener.started?
        end

        def receive_envelopes
          @world.persistence.pull_envelopes(@world.id).each do |envelope|
            self << envelope
          end
        rescue => e
          log(Logger::ERROR, "Receiving envelopes failed on #{e}")
        end

        def send_envelope(envelope)
          @world.persistence.push_envelope(envelope)
          if @postgres_listener.enabled?
            @postgres_listener.notify(envelope.receiver_id)
          end
        rescue => e
          log(Logger::ERROR, "Sending envelope failed on #{e}")
        end

        def update_receiver_id(envelope, new_receiver_id)
          Dispatcher::Envelope[envelope.request_id, envelope.sender_id, new_receiver_id, envelope.message]
        end

        def find_receiver(envelope)
          if Dispatcher::AnyExecutor === envelope.receiver_id
            any_executor
          else
            envelope.receiver_id
          end
        end

        def any_executor
          executors = @world.persistence.find_worlds(:filters => { :executor => true }, :order_by => :id)
          @round_robin_counter += 1
          if executors.any?
            @round_robin_counter %= executors.size
            executors[@round_robin_counter].id
          else
            raise Dynflow::Error, "No executor available"
          end
        end
      end

      def initialize(world = nil, polling_interval = 1)
        @core  = Core.spawn('connector-database-core', polling_interval)
        start_listening(world) if world
      end

      def start_listening(world)
        @core.ask(StartListening[world])
      end

      def stop_listening(world)
        @core.ask(StopListening[world])
      end

      def send(envelope)
        @core.ask(envelope)
      end

      def terminate
        @core.ask(:terminate!)
      end
    end
  end
end
