require 'multi_json'
require 'socket'

module Dynflow
  module Executors
    class RemoteViaSocket < Abstract

      Message = Algebrick.type do
        Execute      = type { fields request_id: Integer, execution_plan_uuid: String }
        Confirmation = type do
          Accepted = type { fields request_id: Integer }
          Failed   = type { fields request_id: Integer, error: String }

          variants Accepted, Failed
        end
        Done         = type { fields request_id: Integer, execution_plan_uuid: String }

        variants Execute, Confirmation, Done
      end

      module Serialization
        def dump(obj)
          MultiJson.dump(obj.to_hash)
        end

        def load(str)
          Message.from_hash MultiJson.load(str)
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

      include Serialization

      class Listener < Dynflow::Listeners::Abstract
        include Serialization
        include Algebrick::Matching

        def initialize(world, socket_path)
          super(world)

          # TODO set socket rights
          File.delete socket_path if File.exist? socket_path
          @server = UNIXServer.new socket_path

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

      include Algebrick::Matching

      def initialize(world, socket_path)
        super world

        @socket           = nil
        @socket_barrier   = Mutex.new
        @socket_path      = is_kind_of! socket_path, String
        @last_id          = 0
        @finished_futures = {}
        @accepted_futures = {}
        @thread           = Thread.new { loop { listen } }
      end

      def execute(execution_plan_id, future = Future.new)
        id                    = @last_id += 1
        @finished_futures[id] = future

        socket do |socket|
          if socket
            send_message socket, Execute[id, execution_plan_id]
          else
            # TODO store some limited number of EPs until it reconnects? it'll block
            # Or give it a few seconds?
            raise Dynflow::Error, 'Connection is gone.'
          end
        end

        @accepted_futures[id] = accepted = Future.new
        if accepted.value.is_a? Exception
          @finished_futures.delete id
          raise accepted.value
        end

        return future
      end

      def update_progress(suspended_action, done, *args)
        raise NotImplementedError
      end

      private

      def socket=(val)
        @socket_barrier.synchronize { @socket = val }
      end

      def socket
        @socket_barrier.synchronize do
          yield @socket
        end
      end

      def connect
        self.socket = UNIXSocket.new @socket_path
        logger.info 'Connected.'
      rescue => error
        logger.warn error
        sleep 1
        retry
      end

      def listen
        connect unless @socket
        match message = receive_message(@socket),
              Accepted.(~any) >-> id do
                @accepted_futures.delete(id).set true
              end,
              Failed.(~any, ~any) >-> id, error do
                @accepted_futures.delete(id).set Dynflow::Error.new(error)
              end,
              Done.(~any, ~any) >-> id, uuid do
                execution_plan = world.persistence.load_execution_plan(uuid)
                @finished_futures.delete(id).set execution_plan
              end,
              NilClass.to_m >-> do
                self.socket = nil
                logger.info 'Disconnected.'
              end
      rescue => error
        logger.fatal error
      end
    end
  end
end
