module Dynflow
  module Connectors
    class Database < Abstract

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
                @core << :check_inbox
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

      class Core < Actor
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

        def start_listening(world)
          @world = world
          @stopped = false
          @postgres_listener ||= PostgresListerner.new(self, @world.id, @world.persistence.adapter.db)
          postgres_listen_start
          self << :periodic_check_inbox
        end

        def stop_listening(world)
          @stopped = true
          postgres_listen_stop
        end

        def periodic_check_inbox
          self << :check_inbox
          @world.clock.ping(self, polling_interval, :periodic_check_inbox) unless @stopped
        end

        def check_inbox
          return unless @world
          receive_envelopes
        end

        def handle_envelope(envelope)
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
        end

        private

        def postgres_listen_start
          @postgres_listener.start if @postgres_listener.enabled? && !@postgres_listener.started?
        end

        def postgres_listen_stop
          @postgres_listener.stop if @postgres_listener.started?
        end

        def receive_envelopes
          @world.persistence.pull_envelopes(@world.id).each do |envelope|
            self.tell([:handle_envelope, envelope])
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
        @core.ask([:start_listening, world])
      end

      def stop_listening(world)
        @core.ask([:stop_listening, world])
      end

      def send(envelope)
        @core.ask([:handle_envelope, envelope])
      end

      def terminate
        @core.ask(:terminate!)
      end
    end
  end
end
