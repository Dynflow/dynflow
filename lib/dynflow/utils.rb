module Dynflow
  module Utils

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

    # Heaviliy inpired by ActiveSupport::HashWithIndifferentAccess,
    # reasons we don't want to use the original implementation:
    #   1. we don't want any core_ext extensions
    #   2. some users are not happy about seeing the ActiveSupport as
    #   our depednency
    class IndifferentHash < Hash
      def initialize(constructor = {})
        if constructor.respond_to?(:to_hash)
          super()
          update(constructor)
        else
          super(constructor)
        end
      end

      def default(key = nil)
        if key.is_a?(Symbol) && include?(key = key.to_s)
          self[key]
        else
          super
        end
      end

      def self.[](*args)
        new.merge!(Hash[*args])
      end

      alias_method :regular_writer, :[]= unless method_defined?(:regular_writer)
      alias_method :regular_update, :update unless method_defined?(:regular_update)

      def []=(key, value)
        regular_writer(convert_key(key), convert_value(value, for: :assignment))
      end

      alias_method :store, :[]=

      def update(other_hash)
        if other_hash.is_a? IndifferentHash
          super(other_hash)
        else
          other_hash.to_hash.each_pair do |key, value|
            if block_given? && key?(key)
              value = yield(convert_key(key), self[key], value)
            end
            regular_writer(convert_key(key), convert_value(value))
          end
          self
        end
      end

      alias_method :merge!, :update

      def key?(key)
        super(convert_key(key))
      end

      alias_method :include?, :key?
      alias_method :has_key?, :key?
      alias_method :member?, :key?

      def fetch(key, *extras)
        super(convert_key(key), *extras)
      end

      def values_at(*indices)
        indices.collect { |key| self[convert_key(key)] }
      end

      def dup
        self.class.new(self).tap do |new_hash|
          new_hash.default = default
        end
      end

      def merge(hash, &block)
        self.dup.update(hash, &block)
      end

      def reverse_merge(other_hash)
        super(self.class.new_from_hash_copying_default(other_hash))
      end

      def reverse_merge!(other_hash)
        replace(reverse_merge( other_hash ))
      end

      def replace(other_hash)
        super(self.class.new_from_hash_copying_default(other_hash))
      end

      def delete(key)
        super(convert_key(key))
      end

      def stringify_keys!; self end
      def deep_stringify_keys!; self end
      def stringify_keys; dup end
      def deep_stringify_keys; dup end
      def to_options!; self end

      def select(*args, &block)
        dup.tap { |hash| hash.select!(*args, &block) }
      end

      def reject(*args, &block)
        dup.tap { |hash| hash.reject!(*args, &block) }
      end

      # Convert to a regular hash with string keys.
      def to_hash
        _new_hash = Hash.new(default)
        each do |key, value|
          _new_hash[key] = convert_value(value, for: :to_hash)
        end
        _new_hash
      end

      protected
      def convert_key(key)
        key.kind_of?(Symbol) ? key.to_s : key
      end

      def convert_value(value, options = {})
        if value.is_a? Hash
          if options[:for] == :to_hash
            value.to_hash
          else
            Utils.indifferent_hash(value)
          end
        elsif value.is_a?(Array)
          unless options[:for] == :assignment
            value = value.dup
          end
          value.map! { |e| convert_value(e, options) }
        else
          value
        end
      end
    end
  end
end
