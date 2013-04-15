require 'forwardable'
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/core_ext/string/inflections'
require 'apipie-params'

module Eventum
  class Message

    def ==(other)
      self.encode == other.encode
    end

    extend Forwardable

    def_delegators :@data, '[]', '[]='

    attr_reader :data

    def initialize(data = {})
      @data = data.with_indifferent_access
    end


    def self.decode(data)
      ret = data['message_type'].constantize.allocate
      ret.instance_variable_set("@data", data['data'])
      return ret
    end

    def encode
      {
        'message_type' => self.class.name,
        'data' => @data
      }
    end

  end
end
