module Dynflow
  module Executors
    class RemoteViaSocket < Abstract
      class Core < MicroActor
        include Listeners::Serialization

        Message = Algebrick.type do
          variants Closed    = atom,
                   Received  = type { fields message: Protocol::Response },
                   Event     = Executors::Abstract::Event,
                   Execution = Executors::Abstract::Execution
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
                      (on Protocol::Execution.(execution_plan_id: ~any) do |uuid|
                        world.persistence.load_execution_plan(uuid)
                      end),
                      (on Protocol::Event do
                        raise NotImplementedError
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
          disconnect
        end

        def on_message(message)
          Type! message, Message
          match message,
                (on Execution.(~any, ~any) do |execution_plan_uuid, future|
                  raise 'terminating' if terminating?
                  job          = Job::Execution[execution_plan_uuid]
                  id, accepted = add_tracked_job future, job
                  success      = connect && begin
                    send_message @socket, Message::Do[id, job]
                    true
                  rescue IOError => error
                    logger.warn error
                    false
                  end

                  unless success
                    @tracked_jobs[id].reject! Dynflow::Error.new(
                                                  'No connection to RemoteViaSocket::Listener')
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
                  @tracked_jobs.each { |_, c| c.fail! 'No connection to RemoteViaSocket::Listener' }
                  @tracked_jobs.clear
                  terminate! if terminating?
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
