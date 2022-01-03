# frozen_string_literal: true
require_relative 'test_helper'
require 'active_support/time'

module Dynflow
  module ExtensionsTest
    describe 'msgpack extensions' do
      it 'allows {de,}serializing Time' do
        ::Time.stub(:zone, ActiveSupport::TimeZone['Europe/Prague']) do
          time = Time.now
          transformed = MessagePack.unpack(time.to_msgpack)
          assert_equal transformed, time
          assert_equal transformed.class, time.class
        end
      end

      it 'allows {de,}serializing ActiveSupport::TimeWithZone' do
        ::Time.stub(:zone, ActiveSupport::TimeZone['Europe/Prague']) do
          time = Time.zone.now
          transformed = MessagePack.unpack(time.to_msgpack)
          assert_equal transformed, time
          assert_equal transformed.class, time.class
        end
      end

      it 'allows {de,}serializing DateTime' do
        ::Time.stub(:zone, ActiveSupport::TimeZone['Europe/Prague']) do
          time = DateTime.now
          transformed = MessagePack.unpack(time.to_msgpack)
          assert_equal transformed, time
          assert_equal transformed.class, time.class
        end
      end

      it 'allows {de,}serializing Date' do
        ::Time.stub(:zone, ActiveSupport::TimeZone['Europe/Prague']) do
          date = DateTime.current
          transformed = MessagePack.unpack(date.to_msgpack)
          assert_equal transformed, date
          assert_equal transformed.class, date.class
        end
      end
    end
  end
end
