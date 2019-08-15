# frozen_string_literal: true
module Dynflow
  module Utils
    # Heavily inspired by rubyworks/pqueue
    class PriorityQueue
      def initialize(&block) # :yields: a, b
        @backing_store = []
        @comparator = block || :<=>.to_proc
      end

      def size
        @backing_store.size
      end

      def top
        @backing_store.last
      end

      def push(element)
        @backing_store << element
        reposition_element(@backing_store.size - 1)
      end

      def pop
        @backing_store.pop
      end

      def to_a
        @backing_store
      end

      private

      # The element at index k will be repositioned to its proper place.
      def reposition_element(index)
        return if size <= 1

        element = @backing_store.delete_at(index)
        index = binary_index(@backing_store, element)

        @backing_store.insert(index, element)
      end

      # Find index where a new element should be inserted using binary search
      def binary_index(array, target)
        upper = array.size - 1
        lower = 0

        while upper >= lower
          center = lower + (upper - lower) / 2

          case @comparator.call(target, array[center])
          when 0
            return center
          when 1
            lower = center + 1
          when -1
            upper = center - 1
          end
        end
        lower
      end
    end
  end
end
