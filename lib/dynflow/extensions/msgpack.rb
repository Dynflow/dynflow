# frozen_string_literal: true
require 'msgpack'

module Dynflow
  module Extensions
    module MsgPack
      module Time
        def to_msgpack(out = ''.dup)
          ::MessagePack.pack(self, out)
          out
        end
      end

      ::Time.include ::Dynflow::Extensions::MsgPack::Time
      ::MessagePack::DefaultFactory.register_type(0x00, Time, packer: MessagePack::Time::Packer, unpacker: MessagePack::Time::Unpacker)

      begin
        require 'active_support/time_with_zone'
        unpacker = ->(payload) do
          tv = MessagePack::Timestamp.from_msgpack_ext(payload)
          ::Time.zone.at(tv.sec, tv.nsec, :nanosecond)
        end
        ::ActiveSupport::TimeWithZone.include ::Dynflow::Extensions::MsgPack::Time
        ::MessagePack::DefaultFactory.register_type(0x01, ActiveSupport::TimeWithZone, packer: MessagePack::Time::Packer, unpacker: unpacker)

        ::DateTime.include ::Dynflow::Extensions::MsgPack::Time
        ::MessagePack::DefaultFactory.register_type(0x02, DateTime,
                                                    packer: ->(datetime) { MessagePack::Time::Packer.(datetime.to_time) },
                                                    unpacker: ->(payload) { unpacker.(payload).to_datetime })
      rescue LoadError
        # This is fine
        nil
      end
    end
  end
end
