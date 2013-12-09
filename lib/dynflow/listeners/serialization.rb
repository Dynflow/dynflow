module Dynflow
  module Listeners
    module Serialization
      SocketMessage = Algebrick.type do
        Execute      = type { fields request_id: Integer, execution_plan_uuid: String }
        Confirmation = type do
          variants Accepted = type { fields request_id: Integer },
                   Failed   = type { fields request_id: Integer, error: String }
        end
        Done         = type { fields request_id: Integer, execution_plan_uuid: String }

        variants Execute, Confirmation, Done
      end

      def dump(obj)
        MultiJson.dump(obj.to_hash)
      end

      def load(str)
        SocketMessage.from_hash MultiJson.load(str)
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
      rescue IOError
        nil
      end
    end
  end
end
