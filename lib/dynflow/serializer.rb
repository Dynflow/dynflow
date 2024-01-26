# frozen_string_literal: true

require 'algebrick/serializer'

module Dynflow
  def self.serializer
    @serializer ||= Serializer.new
  end

  class Serializer < Algebrick::Serializer
    ARBITRARY_TYPE_KEY = :class
    MARSHAL_KEY        = :marshaled

    def load(data, options = {})
      case data
      when ::Array
        data.collect { |v| load(v) }
      else
        super
      end
    end

    def dump(object, options = {})
      case object
      when ::Array
        object.collect { |v| dump(v) }
      else
        super
      end
    end

    protected

    def parse_other(other, options = {})
      if Hash === other
        if (marshal_value = other[MARSHAL_KEY] || other[MARSHAL_KEY.to_s])
          return Marshal.load(Base64.strict_decode64(marshal_value))
        end

        if (type_name = other[ARBITRARY_TYPE_KEY] || other[ARBITRARY_TYPE_KEY.to_s])
          if type_name == 'Time' && ( time_str = other['value'] )
            return Serializable.send(:string_to_time, time_str)
          end
          type = Utils.constantize(type_name) rescue nil
          if type && type.respond_to?(:from_hash)
            return type.from_hash other
          end
        end
      end

      return other
    end

    def generate_other(object, options = {})
      hash = case
             when object.respond_to?(:to_h)
               object.to_h
             when object.respond_to?(:to_hash)
               object.to_hash
             when object.is_a?(Time) && !options[:marshaled_time]
               { ARBITRARY_TYPE_KEY => 'Time', 'value' => object.utc.strftime(Serializable::TIME_FORMAT) }
             else
               { ARBITRARY_TYPE_KEY => object.class.to_s,
                 MARSHAL_KEY        => Base64.strict_encode64(Marshal.dump(object)) }
             end
      raise "Missing #{ARBITRARY_TYPE_KEY} key in #{hash.inspect}" unless hash.key?(ARBITRARY_TYPE_KEY)
      hash
    end
  end
end
