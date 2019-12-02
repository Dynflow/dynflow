module Dynflow
  module Utils
    class LeafTree
      def initialize(dependencies = {})
        @dependencies = dependencies
      end

      def leaves
        @dependencies.select { |k, v| v.empty? }.keys
      end

      def empty?
        @dependencies.empty?
      end

      def pluck(to_pluck = leaves)
        to_pluck = [to_pluck] unless to_pluck.kind_of? Array
        # to_pluck = to_pluck & leaves
        return [] if to_pluck.empty?
        @dependencies.each { |k, v| @dependencies[k] = v - to_pluck }
        to_pluck.each { |leaf| @dependencies.delete leaf }
        to_pluck
      end

      def add(dependee, dependers)
        dependers = [dependers] unless dependers.kind_of? Array
        @dependencies[dependee] = (@dependencies[dependee] || []) | dependers.flatten
      end
    end
  end
end
