module Dynflow
  module Executors
    class RemoteViaSocket < Abstract
      class Core < MicroActor
        include Listeners::Serialization

        Message = Algebrick.type do
          Job = Algebrick.type do
            variants Event     = Executors::Abstract::Event,
                     Execution = Executors::Abstract::Execution
          end

          variants Closed   = atom,
                   Received = type { fields message: Protocol::Response },
                   Connect  = atom,
                   Job
        end

        TrackedJob = Algebrick.type do
          fields! id: Integer, job: Protocol::Job, accepted: Future, finished: Future
        end

        module TrackedJob
          def accept!
            accepted.resolve true
            self
          end

          def reject!(error)
            accepted.fail error
            finished.fail error
            self
          end

          def success!(world)
            raise unless accepted.ready?
            finished.resolve(
                match job,
                      (on Core::Protocol::Execution.(execution_plan_id: ~any) do |uuid|
                        world.persistence.load_execution_plan(uuid)
                      end),
                      (on Core::Protocol::Event do
                        true
                      end))
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
          @socket_path  = Type! socket_path, String
          @world        = Type! world, World
          @socket       = nil
          @last_id      = 0
          @tracked_jobs = {}
          connect
        end

        def termination
          terminate! if disconnect
        end

        def on_message(message)
          Type! message, Message
          match message,
                (on ~Job do |job|
                  raise 'terminating' if terminating?
                  job, future  =
                      match job,
                            (on ~Execution do |(execution_plan_uuid, future)|
                              [Protocol::Execution[execution_plan_uuid], future]
                            end),
                            (on ~Event do |(execution_plan_id, step_id, event, future)|
                              [Protocol::Event[execution_plan_id, step_id, event], future]
                            end)
                  id, accepted = add_tracked_job future, job
                  success      = connect && begin
                    send_message @socket, Protocol::Do[id, job]
                    true
                  rescue IOError => error
                    logger.warn error
                    false
                  end

                  unless success
                    @tracked_jobs[id].reject!(
                        Dynflow::Error.new(
                            "Cannot do #{message}, no connection to a Listener"))
                  end

                  return accepted
                end),

                (on Received.(~Protocol::Accepted) do |(id)|
                  @tracked_jobs[id].accept!
                end),

                (on Received.(~Protocol::Failed) do |(id, error)|
                  @tracked_jobs.delete(id).reject! Dynflow::Error.new(error)
                end),

                (on Received.(~Protocol::Done) do |(id)|
                  @tracked_jobs.delete(id).success! @world
                end),

                (on Closed do
                  @socket = nil
                  logger.info 'Disconnected from server.'
                  @tracked_jobs.each do |_, c|
                    c.fail! 'Connection to a Listener lost.'
                  end
                  @tracked_jobs.clear
                  terminate! if terminating?
                end),

                (on Connect do
                  connect
                end)
        end

        def add_tracked_job(finished, job)
          @tracked_jobs[id = (@last_id += 1)] = TrackedJob[id, job, accepted = Future.new, finished]
          return id, accepted
        end

        def connect
          return true if @socket
          @socket = UNIXSocket.new @socket_path
          logger.info 'Connected to server.'
          read_socket_until_closed
          true
        rescue SystemCallError, IOError => error
          logger.warn error
          false
        rescue Errno::ENOENT, Errno::ECONNREFUSED => error # No such file or directory/ Conn. refused
          logger.warn 'Socket unavailable: Attempting to recreate the socket for the next connection'
          Dynflow::Listeners::Socket.new(@world, @socket_path)
          false
        rescue => error
          logger.fatal error
          raise error
        end

        def disconnect
          return true unless @socket

          @socket.close
          false
        rescue Errno::ENOTCONN
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
                Protocol::Message >-> { self << Received[message] },
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
