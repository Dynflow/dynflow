module Dynflow
  class Serializable
    def self.from_hash(hash, *args)
      check_class_key_present hash
      hash[:class].constantize.new_from_hash(hash, *args)
    end

    def to_hash
      raise NotImplementedError
    end

    # @api private
    def self.new_from_hash(hash, *args)
      raise NotImplementedError
      # new ...
    end

    def self.check_class_matching(hash)
      check_class_key_present hash
      unless self.to_s == hash[:class]
        raise ArgumentError, "class mismatch #{hash[:class]} != #{self}"
      end
    end

    def self.check_class_key_present(hash)
      raise ArgumentError, 'missing :class' unless hash[:class]
    end

    private_class_method :check_class_matching, :check_class_key_present

    private

    def recursive_to_hash(value)
      case value
      when Numeric, String, Symbol, TrueClass, FalseClass, NilClass
        value
      when Array
        value.map { |v| recursive_to_hash v }
      when Hash
        value.inject({}) { |h, (k, v)| h.update k => recursive_to_hash(v) }
      else
        value.to_hash
      end
    end

    def self.string_to_time(string)
      return nil if string.nil?
      DateTime.parse(string).to_time
    end
  end
end
