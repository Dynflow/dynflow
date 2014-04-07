module Dynflow
  module Listeners
    module Serialization
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

        module Event
          # TODO fix the workaround
          # marshal and then use base64 because not all json libs can correctly escape binary data
          def to_hash
            super.update event: Base64.strict_encode64(Marshal.dump(event))
          end

          def self.product_from_hash(hash)
            super(hash.merge 'event' => Marshal.load(Base64.strict_decode64(hash.fetch('event'))))
          end
        end
      end

      def dump(obj)
        MultiJson.dump(obj.to_hash)
      end

      def load(str)
        Protocol::Message.from_hash MultiJson.load(str)
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
