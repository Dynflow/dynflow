module Dynflow
  module Listeners
    module Serialization
      SERIALIZER = Serializer.new

      module Protocol

        Job = Algebrick.type do
          Event = type do
            fields! execution_plan_id: String,
                    step_id:           Fixnum,
                    event:             Object
          end

          Execution = type do
            fields! execution_plan_id: String
          end

          variants Event, Execution
        end

        Message = Algebrick.type do
          Request = type do
            variants Do = type { fields request_id: Integer, job: Job }
          end

          Response = type do
            variants Accepted = type { fields request_id: Integer },
                     Failed   = type { fields request_id: Integer, error: String },
                     Done     = type { fields request_id: Integer }
          end

          variants Request, Response
        end
      end

      def dump(obj)
        MultiJson.dump(SERIALIZER.dump(obj))
      end

      def load(str)
        SERIALIZER.load MultiJson.load(str)
      end

      def send_message(io, message, barrier = nil)
        barrier.lock if barrier
        io.puts dump(message)
        true
      rescue SystemCallError => error
        @logger.warn "message could not be sent #{message} because #{error}"
        false
      ensure
        barrier.unlock if barrier
      end

      def receive_message(io)
        if (message = io.gets)
          load(message)
        else
          nil
        end
      rescue IOError
        nil
      end
    end
  end
end
