# frozen_string_literal: true
module Dynflow
  module Utils

    require 'dynflow/utils/indifferent_hash'
    require 'dynflow/utils/priority_queue'

    def self.validate_keys!(hash, *valid_keys)
      valid_keys.flatten!
      unexpected_options = hash.keys - valid_keys - valid_keys.map(&:to_s)
      unless unexpected_options.empty?
        raise ArgumentError, "Unexpected options #{unexpected_options.inspect}. "\
            "Valid keys are: #{valid_keys.map(&:inspect).join(', ')}"
      end
      hash
    end

    def self.symbolize_keys(hash)
      return hash.symbolize_keys if hash.respond_to?(:symbolize_keys)
      hash.reduce({}) do |new_hash, (key, value)|
        new_hash.update(key.to_sym => value)
      end
    end

    def self.stringify_keys(hash)
      return hash.stringify_keys if hash.respond_to?(:stringify_keys)
      hash.reduce({}) do |new_hash, (key, value)|
        new_hash.update(key.to_s => value)
      end
    end

    # Inspired by ActiveSupport::Inflector
    def self.constantize(string)
      return string.constantize if string.respond_to?(:constantize)

      names = string.split('::')

      # Trigger a built-in NameError exception including the ill-formed constant in the message.
      Object.const_get(string) if names.empty?

      # Remove the first blank element in case of '::ClassName' notation.
      names.shift if names.size > 1 && names.first.empty?

      names.inject(Object) do |constant, name|
        if constant == Object
          constant.const_get(name)
        else
          candidate = constant.const_get(name)
          next candidate if constant.const_defined?(name, false)
          next candidate unless Object.const_defined?(name)

          # Go down the ancestors to check if it is owned directly. The check
          # stops when we reach Object or the end of ancestors tree.
          constant = constant.ancestors.inject do |const, ancestor|
            break const    if ancestor == Object
            break ancestor if ancestor.const_defined?(name, false)
            const
          end

          # owner is in Object, so raise
          constant.const_get(name, false)
        end
      end
    end

    def self.indifferent_hash(hash)
      if defined? ::HashWithIndifferentAccess
        # the users already have it: lets give them what they are used to
        ::HashWithIndifferentAccess.new(hash)
      else
        if hash.is_a? IndifferentHash
          return hash
        else
          IndifferentHash.new(hash)
        end
      end
    end
  end
end
