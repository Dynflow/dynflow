# frozen_string_literal: true

module Dynflow
  class Director
    class QueueHash
      include Algebrick::TypeCheck

      def initialize(key_type = Object, value_type = Object)
        @key_type = key_type
        @value_type = value_type
        @stash = Hash.new { |hash, key| hash[key] = [] }
      end

      def push(key, value)
        Type! key, @key_type
        Type! value, @value_type
        @stash[key].push value
      end

      def shift(key)
        return nil unless present? key
        @stash[key].shift.tap { @stash.delete(key) if @stash[key].empty? }
      end

      def present?(key)
        @stash.key?(key)
      end

      def empty?(key)
        !present?(key)
      end

      def clear
        ret = @stash.dup
        @stash.clear
        ret
      end

      def size(key)
        return 0 if empty?(key)
        @stash[key].size
      end

      def first(key)
        return nil if empty?(key)
        @stash[key].first
      end
    end
  end
end
