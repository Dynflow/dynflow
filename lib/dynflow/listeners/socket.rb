module Dynflow
  module Listeners
    class Socket < Abstract
      # TODO terminate when exiting
      include Listeners::Serialization
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
                  (on ~Protocol::Do do |(id, job)|
                    execute_job(readable, id, job)
                  end),
                  (on NilClass.to_m do
                    remove_client readable
                    logger.info 'Client disconnected.'
                  end)
          end
        end
      rescue => error
        logger.fatal error
      end

      def execute_job(readable, id, job)
        responded = false
        respond   = -> error = nil do
          unless responded
            responded = true
            send_message_to_client(readable, if error
                                               logger.error error
                                               Protocol::Failed[id, error.message]
                                             else
                                               Protocol::Accepted[id]
                                             end)
          end
        end

        future = Future.new.do_then do |_|
          if future.resolved?
            respond.call
            send_message_to_client readable, Protocol::Done[id]
          else
            respond.call future.value
          end
        end

        match job,
              (on ~Protocol::Execution do |(uuid)|
                @world.execute(uuid, future)
              end),
              (on ~Protocol::Event do |(uuid, step_id, event)|
                @world.event(uuid, step_id, event, future)
              end)
        respond.call
      rescue Dynflow::Error => e
        respond.call e
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
  end
end
