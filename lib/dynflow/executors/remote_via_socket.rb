require 'multi_json'
require 'socket'

module Dynflow
  module Executors
    class RemoteViaSocket < Abstract

      SocketMessage = Algebrick.type do
        Execute      = type { fields request_id: Integer, execution_plan_uuid: String }
        Confirmation = type do
          variants Accepted = type { fields request_id: Integer },
                   Failed   = type { fields request_id: Integer, error: String }
        end
        Done         = type { fields request_id: Integer, execution_plan_uuid: String }

        variants Execute, Confirmation, Done
      end

      module Serialization
        def dump(obj)
          MultiJson.dump(obj.to_hash)
        end

        def load(str)
          SocketMessage.from_hash MultiJson.load(str)
        end

        def send_message(io, message, barrier = nil)
          barrier.lock if barrier
          io.puts dump(message)
        ensure
          barrier.unlock if barrier
        end

        def receive_message(io)
          if (message = io.gets)
            load(message)
          else
            nil
          end
        end
      end

      class Listener < Dynflow::Listeners::Abstract
        include Serialization
        include Algebrick::Matching

        def initialize(world, socket_path)
          super(world)

          File.delete socket_path if File.exist? socket_path
          @server = UNIXServer.new socket_path
          File.chmod(0600, socket_path)

          @clients         = []
          @client_barriers = {}
          @loop            = Thread.new { loop { listen } }
        end

        private

        def listen
          ios                   = [@server, *@clients]
          reads, writes, errors = IO.select(ios, [], ios)
          reads.each do |readable|

            if readable == @server
              add_client @server.accept
              logger.info 'Client connected.'

            else
              match message = receive_message(readable),
                    Execute.(~any, ~any) >-> id, uuid do
                      begin
                        @world.execute(uuid,
                                       FutureTask.new do |_|
                                         send_message_to_client readable, Done[id, uuid]
                                       end)
                        send_message_to_client readable, Accepted[id]
                      rescue Dynflow::Error => e
                        send_message_to_client readable, Failed[id, e.message]
                      end
                    end,
                    NilClass.to_m >-> do
                      remove_client readable
                      logger.info 'Client disconnected.'
                    end
            end
          end
        rescue => error
          logger.fatal error
        end

        def add_client(client)
          @clients << client
          @client_barriers[client] = Mutex.new
        end

        def remove_client(client)
          @clients.delete client
          @client_barriers.delete client
        end

        def send_message_to_client(client, message)
          send_message client, message, @client_barriers[client]
        end
      end

      class Manager
        include Algebrick::TypeCheck

        def initialize(persistence)
          @world            = is_kind_of! persistence, Dynflow::World
          @last_id          = 0
          @finished_futures = {}
          @accepted_futures = {}
        end

        def add(future)
          id                    = @last_id += 1
          @finished_futures[id] = future
          @accepted_futures[id] = accepted = Future.new
          return id, accepted
        end

        def accepted(id)
          @accepted_futures.delete(id).set true
        end

        def failed(id, error)
          @finished_futures.delete id
          @accepted_futures.delete(id).set Dynflow::Error.new(error)
        end

        def finished(id, uuid)
          @finished_futures.delete(id).set @world.persistence.load_execution_plan(uuid)
        end
      end

      class Core < MicroActorWithFutures
        include Serialization

        Message = Algebrick.type do
          variants Closed   = atom,
                   Received = type { fields message: SocketMessage },
                   Execute  = type { fields execution_plan_uuid: String, future: Future }
        end

        def initialize(world, socket_path)
          super(world.logger)
          @socket_path = is_kind_of! socket_path, String
          @manager     = Manager.new world
          @socket      = nil
          connect
        end

        private

        def on_message(message)
          match message,
                Closed >-> do
                  @socket = nil
                  logger.info 'Disconnected.'
                end,
                Received.(Accepted.(~any)) >-> id { @manager.accepted id },
                Received.(Failed.(~any, ~any)) >-> id, error { @manager.failed id, error },
                Received.(Done.(~any, ~any)) >-> id, uuid { @manager.finished id, uuid },
                Core::Execute.(~any, ~any) >-> execution_plan_uuid, future do
                  id, accepted = @manager.add future
                  success      = connect && begin
                    send_message @socket, RemoteViaSocket::Execute[id, execution_plan_uuid]
                    true
                  rescue IOError => error
                    logger.warn error
                    false
                  end
                  @manager.failed id, 'No connection to RemoteViaSocket::Listener' unless success

                  return accepted
                end
        end

        def connect
          return true if @socket
          @socket = UNIXSocket.new @socket_path
          logger.info 'Connected.'
          read_socket_until_closed
          true
        rescue IOError => error
          logger.warn error
          false
        end

        def read_socket_until_closed
          Thread.new do
            catch(:stop_reading) do
              loop { read_socket }
            end
          end
        end

        def read_socket
          match message = receive_message(@socket),
                SocketMessage >-> { self << Received[message] },
                NilClass.to_m >-> do
                  self << Closed
                  throw :stop_reading
                end
        rescue => error
          logger.fatal error
        end
      end

      include Serialization
      include Algebrick::Matching

      def initialize(world, socket_path)
        super world
        @core = Core.new world, socket_path
      end

      def execute(execution_plan_id, future = Future.new)
        accepted = (@core << Core::Execute[execution_plan_id, future]).value
        raise accepted.value if accepted.value.is_a? Exception
        return future
      end

      def update_progress(suspended_action, done, *args)
        raise 'updates are handled in a process with real executor'
      end
    end
  end
end
