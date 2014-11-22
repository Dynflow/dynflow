module Dynflow
  module Listeners
    class Socket < Abstract
      include Listeners::Serialization
      include Algebrick::Matching

      Terminate = Algebrick.atom

      def initialize(world, socket_path, interval = 1)
        super(world)

        File.delete socket_path if File.exist? socket_path
        @server = UNIXServer.new socket_path
        File.chmod(0600, socket_path)

        @clients         = []
        @client_barriers = {}
        @terminate       = false
        @loop            = Thread.new do
          Thread.current.abort_on_exception = true
          catch(Terminate) { loop { listen(interval) } }
          @terminate.resolve true
        end
      end

      def terminate(future = Concurrent::IVar.new)
        raise 'multiple calls' if @terminate
        @terminate = future
      end

      private

      def listen(interval)
        shutdown if @terminate

        ios                   = [@server, *@clients]
        reads, writes, errors = IO.select(ios, [], ios, interval)
        Array(reads).each do |readable|
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

        future = Concurrent::IVar.new.do_then do |_|
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

      def shutdown
        @clients.each { |c| c.shutdown :RDWR }
        @server.close
      rescue => e
        @logger.error e
      ensure
        throw Terminate
      end
    end
  end
end
