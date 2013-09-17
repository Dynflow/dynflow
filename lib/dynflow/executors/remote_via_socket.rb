require 'multi_json'
require 'socket'

#MultiJson.load
#MultiJson.dump

module Dynflow
  module Executors
    class RemoteViaSocket < Abstract

      Message = Algebrick.type do
        Execute      = Algebrick.type { fields request_id: Integer, execution_plan_uuid: String }
        Confirmation = Algebrick.type do
          Accepted = Algebrick.type { fields request_id: Integer }
          Failed   = Algebrick.type { fields request_id: Integer, error: String }

          variants Accepted, Failed
        end
        Done         = Algebrick.type { fields request_id: Integer, execution_plan_uuid: String }

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
          @world = world

          # TODO set socket rights
          File.delete socket_path if File.exist? socket_path
          @server = UNIXServer.new socket_path

          @clients                    = []
          @notify_read, @notify_write = IO.pipe
          @notify_barrier             = Mutex.new
          @who_to_notify              = {}
          @loop                       = Thread.new { loop { listen } }
        end

        private

        def listen
          ios                   = [@server, @notify_read, *@clients]
          reads, writes, errors = IO.select(ios, [], ios)
          # TODO check for errors and closed connections
          reads.each do |read|

            case read
            when @notify_read
              match message = receive_message(@notify_read),
                    ~Done >-> done do
                      client = @who_to_notify.delete done[:request_id]
                      send_message client, done
                    end

            when @server
              @clients.push @server.accept
              # TODO log to a logger instead
              $stderr.puts 'INFO client connected'

            else
              match message = receive_message(read),
                    Execute.(~any, ~any) >-> id, uuid do
                      @who_to_notify[id] = read
                      begin
                        @world.execute(uuid,
                                       FutureTask.new do |_|
                                         send_message @notify_write, Done[id, uuid], @notify_barrier
                                       end)
                        send_message read, Accepted[id]
                      rescue => e
                        send_message read, Failed[id, e.message]
                      end
                    end,
                    NilClass.to_m >-> do
                      @clients.delete read
                      # TODO log to a logger instead
                      $stderr.puts 'INFO client disconnected'
                    end
            end
          end
        rescue => error
          # TODO log to a logger instead
          $stderr.puts "FATAL #{error.message} (#{error.class})\n#{error.backtrace.join("\n")}"
        end
      end

      include Algebrick::Matching
      include Algebrick::TypeCheck

      def initialize(world, socket_path)
        super world
        @socket           = nil
        @socket_path      = is_kind_of! socket_path, String
        @last_id          = 0
        @finished_futures = {}
        @accepted_futures = {}
        @thread           = Thread.new { loop { listen } }
      end

      def execute(execution_plan_id, future = Future.new)
        id = @last_id += 1
        send_message @socket, Execute[id, execution_plan_id]

        @accepted_futures[id] = accepted = Future.new
        raise accepted.value if accepted.value.is_a? Exception

        @finished_futures[id] = future
      end

      def update_progress(suspended_action, done, *args)
        raise NotImplementedError
      end

      private

      def connect
        @socket = UNIXSocket.new @socket_path
        # TODO log to a logger instead
        $stderr.puts 'INFO connected'
      rescue => error
        # TODO log to a logger instead
        $stderr.puts "WARN #{error.message} (#{error.class})\n#{error.backtrace.join("\n")}"
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
                @socket = nil
                # TODO log to a logger instead
                $stderr.puts 'INFO disconnected'
              end
      rescue => error
        # TODO log to a logger instead
        $stderr.puts "FATAL #{error.message} (#{error.class})\n#{error.backtrace.join("\n")}"
      end
    end
  end
end
