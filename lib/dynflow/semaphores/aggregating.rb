module Dynflow
  module Semaphores
    class Aggregating < Abstract

      attr_reader :children, :waiting

      def initialize(children)
        @children = children
        @waiting  = []
      end

      def wait(thing)
        if get > 0
          true
        else
          @waiting << thing
          false
        end
      end

      def get_waiting
        @waiting.shift
      end

      def has_waiting?
        !@waiting.empty?
      end

      def save
        @children.values.each(&:save)
      end

      def get(n = 1)
        available = free
        if n > available
          drain
        else
          @children.values.each { |child| child.get n }
          n
        end
      end

      def drain
        available = free
        @children.values.each { |child| child.get available }
        available
      end

      def free
        @children.values.map(&:free).reduce { |acc, cur| cur < acc ? cur : acc }
      end

      def release(n = 1, key = nil)
        if key.nil?
          @children.values.each { |child| child.release n }
        else
          @children[key].release n
        end
      end

    end
  end
end
