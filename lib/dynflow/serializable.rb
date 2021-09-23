# frozen_string_literal: true
require 'date'
module Dynflow
  class Serializable
    TIME_FORMAT = '%Y-%m-%d %H:%M:%S.%L'
    LEGACY_TIME_FORMAT = '%Y-%m-%d %H:%M:%S'

    def self.from_hash(hash, *args)
      check_class_key_present hash
      constantize(hash[:class]).new_from_hash(hash, *args)
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
      raise ArgumentError, "missing :class in #{hash.inspect}" unless hash[:class]
    end

    def self.constantize(action_name)
      Utils.constantize(action_name)
    end

    private_class_method :check_class_matching, :check_class_key_present

    private

    # recursively traverses hash-array structure and converts all to hashes
    # accepts more hashes which are then merged
    def recursive_to_hash(*values)
      if values.size == 1
        value = values.first
        case value
        when Hash
          value.inject({}) { |h, (k, v)| h.update k => recursive_to_hash(v) }
        when Array
          value.map { |v| recursive_to_hash v }
        when ->(v) { v.respond_to?(:to_msgpack) }
          value
        else
          value.to_hash
        end
      else
        values.all? { |v| Type! v, Hash, NilClass }
        recursive_to_hash(values.compact.reduce { |h, v| h.merge v })
      end
    end

    def self.string_to_time(string)
      return if string.nil?
      return string if string.is_a?(Time)
      time = begin
               DateTime.strptime(string, TIME_FORMAT)
             rescue ArgumentError => _
               DateTime.strptime(string, LEGACY_TIME_FORMAT)
             end

      time.to_time.utc
    end

    def time_to_str(time)
      return if time.nil?
      Type! time, Time
      time.utc.strftime(TIME_FORMAT)
    end

    def self.hash_to_error(hash)
      return nil if hash.nil?
      ExecutionPlan::Steps::Error.from_hash(hash)
    end

    private_class_method :string_to_time, :hash_to_error
  end
end
