module Dynflow
  module Executors
    class RemoteViaSocket < Abstract
      class Core < MicroActorWithFutures
        include Listeners::Serialization

        Message = Algebrick.type do
          variants Closed   = atom,
                   Finish   = type { fields Future },
                   Received = type { fields message: SocketMessage },
                   Execute  = type { fields execution_plan_uuid: String, future: Future }
        end

        def initialize(world, socket_path)
          super(world.logger, world, socket_path)
        end

        def terminate!
          return true if stopped?
          self << Finish[future = Future.new]
          future.wait
          super
        end

        private

        def delayed_initialize(world, socket_path)
          @socket_path      = Type! socket_path, String
          @manager          = Manager.new world
          @socket           = nil
          @finishing_future = nil
          connect
        end

        def finishing?
          !!@finishing_future
        end

        def on_message(message)
          match message,
                Closed >-> do
                  @socket = nil
                  logger.info 'Disconnected from server.'
                  @finishing_future.resolve true if finishing?
                end,
                Finish.(~any) >-> future do
                  @finishing_future = future
                  disconnect
                end,
                Received.(Accepted.(~any)) >-> id { @manager.accepted id },
                Received.(Failed.(~any, ~any)) >-> id, error { @manager.failed id, error },
                Received.(Done.(~any, ~any)) >-> id, uuid { @manager.finished id, uuid },
                Core::Execute.(~any, ~any) >-> execution_plan_uuid, future do
                  raise 'terminating' if finishing?
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
          logger.info 'Connected to server.'
          read_socket_until_closed
          true
        rescue IOError => error
          logger.warn error
          false
        end

        def disconnect
          return true unless @socket
          @socket.shutdown :RDWR
          true
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
    end
  end
end
