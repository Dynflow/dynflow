module Dynflow
  module Executors
    class RemoteViaSocket < Abstract
      class Core < MicroActor
        include Listeners::Serialization

        Message = Algebrick.type do
          variants Closed   = atom,
                   Received = type { fields message: SocketMessage },
                   Execute  = type { fields execution_plan_uuid: String, future: Future }
        end

        Execution = Algebrick.type do
          fields! id: Integer, accepted: Future, finished: Future
        end

        module Execution
          def accept!
            accepted.resolve true
            self
          end

          def reject!(error)
            accepted.fail error
            finished.fail error
            self
          end

          def success!(value)
            raise unless accepted.ready?
            finished.resolve value
            self
          end

          def fail!(error)
            if accepted.ready?
              finished.fail error
            else
              reject! error
            end
            self
          end
        end

        def initialize(world, socket_path)
          super(world.logger, world, socket_path)
        end

        private

        def delayed_initialize(world, socket_path)
          @socket_path = Type! socket_path, String
          @world       = Type! world, World
          @socket      = nil
          @last_id     = 0
          @executions  = {}
          connect
        end

        def termination
          disconnect
        end

        def on_message(message)
          match message,

                (on Core::Execute.(~any, ~any) do |execution_plan_uuid, future|
                  raise 'terminating' if terminating?
                  id, accepted = add_execution future
                  success      = connect && begin
                    send_message @socket, RemoteViaSocket::Execute[id, execution_plan_uuid]
                    true
                  rescue IOError => error
                    logger.warn error
                    false
                  end

                  unless success
                    @executions[id].reject! Dynflow::Error.new(
                                                'No connection to RemoteViaSocket::Listener')
                  end

                  return accepted
                end),

                (on Received.(Accepted.(~any)) do |id|
                  @executions[id].accept!
                end),

                (on Received.(Failed.(~any, ~any)) do |id, error|
                  @executions.delete(id).reject! Dynflow::Error.new(error)
                end),

                (on Received.(Done.(~any, ~any)) do |id, uuid|
                  @executions.delete(id).success! @world.persistence.load_execution_plan(uuid)
                end),

                (on Closed do
                  @socket = nil
                  logger.info 'Disconnected from server.'
                  @executions.each { |_, c| c.fail! 'No connection to RemoteViaSocket::Listener' }
                  @executions.clear
                  terminate! if terminating?
                end)
        end

        def add_execution(finished)
          @executions[id = (@last_id += 1)] = Execution[id, accepted = Future.new, finished]
          return id, accepted
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
