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
      return if string.nil?
      _, year, month, day, hour, min, sec = */(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/.match(string)
      Time.new(year.to_i, month.to_i, day.to_i, hour.to_i, min.to_i, sec.to_i)
    end

    def time_to_str(time)
      return if time.nil?
      is_kind_of! time, Time
      time.strftime '%Y-%m-%d %H:%M:%S'
    end

    def self.hash_to_error(hash)
      return nil if hash.nil?
      ExecutionPlan::Steps::Error.from_hash(hash)
    end

    private_class_method :string_to_time, :hash_to_error

  end
end
