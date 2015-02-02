module Dynflow
  module Dispatcher
    Job = Algebrick.type do
      Event = type do
        fields! execution_plan_id: String,
                step_id:           Fixnum,
                event:             Object
      end

      Execution = type do
        fields! execution_plan_id: String
      end

      Ping = type do
        fields! receiver_id: String
      end

      variants Event, Execution, Ping
    end

    PublishJob = Algebrick.type do
      fields! future:          Concurrent::IVar,
              job:             Job
    end

    RePublishJob = Algebrick.type do
      fields! job:             Job,
              client_world_id: String,
              request_id:      Integer
    end

    Request = Algebrick.type do
      variants Job
    end

    Response = Algebrick.type do
      variants Accepted = atom,
               Failed   = type { fields! error: String },
               Done     = atom,
               Pong     = atom
    end

    Envelope = Algebrick.type do
      fields! request_id: Integer,
              sender_id: String,
              receiver_id: type { variants String, AnyExecutor = atom },
              message: type { variants Request, Response }
    end

    module Envelope
      def build_response_envelope(response_message, sender)
        Envelope[self.request_id,
                 sender.id,
                 self.sender_id,
                 response_message]
      end
    end

    # TODO: DRY - common for more actors
    StartTerminating = Algebrick.type do
      fields! terminated: Concurrent::IVar
    end

    module Event
      def to_hash
        super.update event: Base64.strict_encode64(Marshal.dump(event))
      end

      def self.product_from_hash(hash)
        super(hash.merge 'event' => Marshal.load(Base64.strict_decode64(hash.fetch('event'))))
      end
    end
  end
end

require 'dynflow/dispatcher/client_dispatcher'
require 'dynflow/dispatcher/executor_dispatcher'
