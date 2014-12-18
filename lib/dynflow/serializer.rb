require 'algebrick/serializer'

module Dynflow
  class Serializer < Algebrick::Serializer

    ARBITRARY_TYPE_KEY = :class
    MARSHAL_KEY        = :marshaled

    protected

    def parse_other(other, options = {})
      if Hash === other &&
          (other.key?(ARBITRARY_TYPE_KEY) || other.key?(ARBITRARY_TYPE_KEY.to_s)) &&
          (other.key?(MARSHAL_KEY) || other.key?(MARSHAL_KEY.to_s))

        type = other[ARBITRARY_TYPE_KEY] || other[ARBITRARY_TYPE_KEY.to_s]
        if type.respond_to? :from_hash
          type.from_hash other
        else
          Marshal.load(Base64.strict_decode64(other[MARSHAL_KEY] || other[MARSHAL_KEY.to_s]))
        end
      else
        other
      end
    end

    def generate_other(object, options = {})
      case
      when object.respond_to?(:to_h)
        object.to_h
      when object.respond_to?(:to_hash)
        object.to_hash
      else
        { ARBITRARY_TYPE_KEY => object.class.to_s,
          MARSHAL_KEY        => Base64.strict_encode64(Marshal.dump(object)) }
      end
    end
  end
end
